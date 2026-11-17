import AppKit
import MactrixUI
import MatrixIntegration
import MatrixProtocols
import MatrixRustSDK
import Utils

/// Shared row chrome. The content view is created once and retained across table reuse.
final class MessageRowView: NSView {
  let contentKind: MessageContentKind
  var onHoverChange: ((MessageRowView, Bool, NSEvent) -> Bool)?
  var onSelectRequest: ((MessageRowView) -> Void)?
  var onArrowKey: ((TimelineSelectionDirection) -> Void)?
  var onMediaPreviewRequest: (() -> Bool)? {
    didSet {
      (contentView as? any MessageMediaPreviewContentView)?.onMediaPreviewRequest =
        onMediaPreviewRequest
    }
  }
  var onMediaPreview: ((URL, MediaFileHandle) -> Void)? {
    didSet {
      (contentView as? any MessageMediaPreviewContentView)?.onMediaPreview = onMediaPreview
    }
  }
  private var isHovered = false
  private var isMessageSelected = false

  // Bubble layout. `bubble` is nil for the standard layout.
  private var bubble: MessageBubblePlacement?
  private var currentContent: MatrixRustSDK.MsgLikeContent?
  private var preferredWidthCache: (maxWidth: CGFloat, width: CGFloat)?
  /// The column that holds the message and its reply preview, thread, reactions and receipts.
  private let columnGuide = NSLayoutGuide()
  private let bubbleBackground = NSView()
  private let groupTimeLabel = NSTextField(labelWithString: "")
  private let senderAvatar = ProfilePictureButton()

  private static var timestampWidth: CGFloat { TimelineTypography.timestampColumnWidth }
  private static var contentHorizontalInset: CGFloat { timestampWidth + 26 }
  private static let replySpacing: CGFloat = 20
  private static let threadSpacing: CGFloat = 10
  private static let reactionSpacing: CGFloat = 10
  private static let receiptSpacing: CGFloat = 10

  private let timestamp = NSTextField(labelWithString: "")
  private let editedLabel = NSTextField(labelWithString: "(edited)")
  private lazy var timestampWidthConstraint = timestamp.widthAnchor.constraint(
    equalToConstant: Self.timestampWidth)
  private let contentView: any MessageContentRowView
  private var replyPreview: MessageReplyPreviewView?
  private var replyDetails: MatrixRustSDK.EmbeddedEventDetails?
  private var replyHeightConstraint: NSLayoutConstraint?

  private lazy var guideLeadingStandard = columnGuide.leadingAnchor.constraint(
    equalTo: timestamp.trailingAnchor, constant: 16)
  private lazy var guideTrailingStandard = columnGuide.trailingAnchor.constraint(
    equalTo: trailingAnchor, constant: -10)
  private lazy var guideLeadingBubble = columnGuide.leadingAnchor.constraint(equalTo: leadingAnchor)
  private lazy var guideWidthBubble = columnGuide.widthAnchor.constraint(equalToConstant: 1)
  private lazy var contentLeadingToGuide = contentView.leadingAnchor.constraint(
    equalTo: columnGuide.leadingAnchor)
  private lazy var contentTrailingToGuide = contentView.trailingAnchor.constraint(
    equalTo: columnGuide.trailingAnchor)
  private lazy var contentWidthBubble = contentView.widthAnchor.constraint(equalToConstant: 1)
  private lazy var timeLeadingToGuide = groupTimeLabel.leadingAnchor.constraint(
    equalTo: columnGuide.leadingAnchor, constant: 4)
  private lazy var timeTrailingToGuide = groupTimeLabel.trailingAnchor.constraint(
    equalTo: columnGuide.trailingAnchor, constant: -4)
  private lazy var avatarSizeConstraints = [
    senderAvatar.widthAnchor.constraint(equalToConstant: MessageBubbleMetrics.avatarSize),
    senderAvatar.heightAnchor.constraint(equalToConstant: MessageBubbleMetrics.avatarSize),
  ]
  private lazy var bubblePaddingConstraints = [
    bubbleBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
    bubbleBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
    bubbleBackground.topAnchor.constraint(equalTo: contentView.topAnchor),
    bubbleBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
  ]

  private var contentTopToReply: NSLayoutConstraint?
  private lazy var contentTopToRow = contentView.topAnchor.constraint(
    equalTo: topAnchor, constant: 4)
  private lazy var contentBottomToRow = contentView.bottomAnchor.constraint(
    equalTo: bottomAnchor, constant: -4)

  private var threadSummaryView: MessageThreadSummaryView?
  private var threadHeightConstraint: NSLayoutConstraint?
  private var threadTopConstraint: NSLayoutConstraint?
  private var threadBottomConstraint: NSLayoutConstraint?

  private var reactionsView: MessageReactionsView?
  private var reactionsHeightConstraint: NSLayoutConstraint?
  private var reactionsTopToContent: NSLayoutConstraint?
  private var reactionsTopToThread: NSLayoutConstraint?
  private var reactionsBottomToRow: NSLayoutConstraint?
  private var reactionsTrailingToContent: NSLayoutConstraint?
  private var reactionsTrailingToReceipts: NSLayoutConstraint?
  private var reactions: [MatrixRustSDK.Reaction] = []

  private var receiptsView: MessageReadReceiptsView?
  private var receiptsWidthConstraint: NSLayoutConstraint?
  private var receiptsHeightConstraint: NSLayoutConstraint?
  private var receiptsTopToContent: NSLayoutConstraint?
  private var receiptsTopToThread: NSLayoutConstraint?
  private var receiptsTopToReactions: NSLayoutConstraint?
  private var receiptsBottomToRow: NSLayoutConstraint?

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  init(
    contentKind: MessageContentKind, contentView: any MessageContentRowView,
    frame frameRect: NSRect = .zero
  ) {
    self.contentKind = contentKind
    self.contentView = contentView
    super.init(frame: frameRect)

    timestamp.font = .systemFont(ofSize: TimelineTypography.scaled(NSFont.labelFontSize))
    timestamp.textColor = .secondaryLabelColor
    timestamp.alignment = .right
    timestamp.translatesAutoresizingMaskIntoConstraints = false

    editedLabel.font = .systemFont(ofSize: TimelineTypography.scaled(10))
    editedLabel.textColor = .secondaryLabelColor
    editedLabel.alignment = .right
    editedLabel.isHidden = true
    editedLabel.translatesAutoresizingMaskIntoConstraints = false

    contentView.translatesAutoresizingMaskIntoConstraints = false
    contentView.onSelectRequest = { [weak self] in
      guard let self else { return }
      self.onSelectRequest?(self)
    }
    contentView.onArrowKey = { [weak self] direction in
      self?.onArrowKey?(direction)
    }

    wantsLayer = true
    layer?.cornerRadius = 4
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: self,
        userInfo: nil
      ))

    bubbleBackground.wantsLayer = true
    bubbleBackground.isHidden = true
    bubbleBackground.translatesAutoresizingMaskIntoConstraints = false

    groupTimeLabel.font = MessageBubbleMetrics.timeFont
    groupTimeLabel.textColor = .secondaryLabelColor
    groupTimeLabel.isHidden = true
    groupTimeLabel.translatesAutoresizingMaskIntoConstraints = false

    senderAvatar.isHidden = true

    addLayoutGuide(columnGuide)
    addSubview(timestamp)
    addSubview(editedLabel)
    addSubview(bubbleBackground)
    addSubview(contentView)
    addSubview(groupTimeLabel)
    addSubview(senderAvatar)

    // NSTableView may retain an old encapsulated height while a reused row is reconfigured.
    contentBottomToRow.priority = .init(999)
    NSLayoutConstraint.activate([
      timestamp.leadingAnchor.constraint(equalTo: leadingAnchor),
      timestamp.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      timestampWidthConstraint,
      editedLabel.leadingAnchor.constraint(equalTo: timestamp.leadingAnchor),
      editedLabel.trailingAnchor.constraint(equalTo: timestamp.trailingAnchor),
      editedLabel.topAnchor.constraint(equalTo: timestamp.bottomAnchor, constant: 1),

      guideLeadingStandard,
      guideTrailingStandard,
      columnGuide.topAnchor.constraint(equalTo: topAnchor),
      columnGuide.bottomAnchor.constraint(equalTo: bottomAnchor),
      contentLeadingToGuide,
      contentTrailingToGuide,
      contentTopToRow,
      contentBottomToRow,

      groupTimeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
      senderAvatar.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: MessageBubbleMetrics.sideInset),
      senderAvatar.bottomAnchor.constraint(equalTo: bubbleBackground.bottomAnchor),
    ])
    NSLayoutConstraint.activate(bubblePaddingConstraints + avatarSizeConstraints)
  }

  func initializeSenderAvatar(
    imageLoader: MactrixUI.ImageLoader?, focusUser: @escaping (_ sender: String) -> Void
  ) {
    senderAvatar.initialize(imageLoader: imageLoader, focusUser: focusUser)
  }

  /// A picker anchor in row coordinates, beside the last reaction or at the content's bottom-left.
  var reactionPickerAnchorRect: NSRect {
    superview?.layoutSubtreeIfNeeded()
    layoutSubtreeIfNeeded()
    if let reactionsView, !reactionsView.isHidden,
      let buttonRect = reactionsView.lastReactionButtonRect
    {
      let rect = convert(buttonRect, from: reactionsView)
      return NSRect(x: rect.maxX, y: rect.minY, width: 1, height: rect.height)
    }
    let rect = convert(contentView.bounds, from: contentView)
    return NSRect(x: rect.minX, y: rect.minY, width: 1, height: 1)
  }

  func configureEditing(_ state: MessageEditState?) {
    contentView.configureEditing(state)
    preferredWidthCache = nil
  }

  func configure(
    event: MatrixRustSDK.EventTimelineItem,
    content: MatrixRustSDK.MsgLikeContent,
    replyDetails: MatrixRustSDK.EmbeddedEventDetails?,
    onReplyClick: (() -> Void)?,
    onThreadClick: (() -> Void)?,
    ownUserId: String?,
    onReactionClick: ((String) -> Void)?,
    roomMembers: [MatrixRustSDK.RoomMember],
    matrixClient: MatrixClient?,
    handleMatrixUri: ((MatrixUriScheme) -> Bool)?,
    bubble: MessageBubblePlacement? = nil
  ) {
    // A reused row may still have its previous table height while its content changes.
    contentBottomToRow.isActive = false
    threadBottomConstraint?.isActive = false
    reactionsBottomToRow?.isActive = false
    receiptsBottomToRow?.isActive = false

    timestamp.font = .systemFont(ofSize: TimelineTypography.scaled(NSFont.labelFontSize))
    editedLabel.font = .systemFont(ofSize: TimelineTypography.scaled(10))
    timestampWidthConstraint.constant = Self.timestampWidth
    receiptsHeightConstraint?.constant = MessageReadReceiptsView.rowHeight
    let date = Date(timeIntervalSince1970: Double(event.timestamp) / 1000)
    timestamp.stringValue = Self.timeFormatter.string(from: date)
    editedLabel.isHidden = !Self.hasBeenEdited(content)
    self.bubble = bubble
    currentContent = content
    preferredWidthCache = nil
    contentView.handleMatrixUri = handleMatrixUri
    contentView.setTextOnAccent(
      bubble?.isOwn == true && MessageBubbleMetrics.usesBackground(contentKind))
    contentView.configure(content: content, matrixClient: matrixClient)
    configureReply(details: replyDetails, onClick: onReplyClick)
    configureThread(summary: content.threadSummary, onClick: onThreadClick)
    configureReactions(event.reactions, ownUserId: ownUserId, onClick: onReactionClick)
    configureReceipts(
      event.userReadReceipts, roomMembers: roomMembers, imageLoader: matrixClient,
      handleMatrixUri: handleMatrixUri)
    configureBubble(event: event, content: content, date: date)
    isHovered = false
    updateBackground()
  }

  // MARK: Bubble layout

  /// Vertical spacing, which differs between the standard and the bubble layout.
  private struct VerticalMetrics {
    /// Space above the content when there is no reply preview.
    var contentTop: CGFloat
    /// Space between the reply preview and the content.
    var replyGap: CGFloat
    /// Extra space between the content and whatever follows it (the bubble's padding).
    var afterContent: CGFloat
    /// Space below the content when nothing follows it.
    var contentBottom: CGFloat
    /// Space below a thread summary, reactions or receipts.
    var otherBottom: CGFloat
    /// The time label below the last bubble of a group.
    var time: CGFloat
  }

  private func verticalMetrics(
    bubble: MessageBubblePlacement?, content: MatrixRustSDK.MsgLikeContent
  ) -> VerticalMetrics {
    guard let bubble else {
      return VerticalMetrics(
        contentTop: 4, replyGap: Self.replySpacing, afterContent: 0, contentBottom: 4,
        otherBottom: 4, time: 0)
    }
    let padding = MessageBubbleMetrics.padding(for: contentKind).height
    let spacing = MessageBubbleMetrics.groupSpacing
    return VerticalMetrics(
      contentTop: spacing + padding, replyGap: 6 + padding, afterContent: padding,
      contentBottom: spacing + padding, otherBottom: 4,
      time: Self.showsTimeLabel(bubble: bubble, content: content)
        ? MessageBubbleMetrics.timeLabelHeight : 0)
  }

  private static func showsTimeLabel(
    bubble: MessageBubblePlacement, content: MatrixRustSDK.MsgLikeContent
  ) -> Bool {
    bubble.isLastInGroup || hasBeenEdited(content)
  }

  private func configureBubble(
    event: MatrixRustSDK.EventTimelineItem, content: MatrixRustSDK.MsgLikeContent, date: Date
  ) {
    let isBubble = bubble != nil
    timestamp.isHidden = isBubble
    if isBubble { editedLabel.isHidden = true }

    NSLayoutConstraint.deactivate([
      guideLeadingStandard, guideTrailingStandard, guideLeadingBubble, guideWidthBubble,
      contentLeadingToGuide, contentTrailingToGuide, contentWidthBubble,
      timeLeadingToGuide, timeTrailingToGuide,
    ])

    guard let bubble else {
      contentLeadingToGuide.constant = 0
      contentTrailingToGuide.constant = 0
      NSLayoutConstraint.activate([
        guideLeadingStandard, guideTrailingStandard, contentLeadingToGuide, contentTrailingToGuide,
      ])
      bubbleBackground.isHidden = true
      groupTimeLabel.isHidden = true
      senderAvatar.isHidden = true
      applyVerticalMetrics(content: content)
      return
    }

    let padding = MessageBubbleMetrics.padding(for: contentKind)
    contentLeadingToGuide.constant = padding.width
    contentTrailingToGuide.constant = -padding.width
    NSLayoutConstraint.activate([
      guideLeadingBubble, guideWidthBubble, contentWidthBubble,
      bubble.isOwn ? contentTrailingToGuide : contentLeadingToGuide,
      bubble.isOwn ? timeTrailingToGuide : timeLeadingToGuide,
    ])
    bubblePaddingConstraints[0].constant = -padding.width
    bubblePaddingConstraints[1].constant = padding.width
    bubblePaddingConstraints[2].constant = -padding.height
    bubblePaddingConstraints[3].constant = padding.height
    bubbleBackground.isHidden = !MessageBubbleMetrics.usesBackground(contentKind)
    updateBubbleColors()

    let edited = Self.hasBeenEdited(content)
    if Self.showsTimeLabel(bubble: bubble, content: content) {
      let time = Self.timeFormatter.string(from: date)
      groupTimeLabel.stringValue =
        switch (bubble.isLastInGroup, edited) {
        case (true, true): String(localized: "\(time) · Edited")
        case (true, false): time
        default: String(localized: "Edited")
        }
      groupTimeLabel.font = MessageBubbleMetrics.timeFont
      groupTimeLabel.alignment = bubble.isOwn ? .right : .left
      groupTimeLabel.isHidden = false
    } else {
      groupTimeLabel.isHidden = true
    }

    senderAvatar.isHidden = !bubble.showsAvatar
    if bubble.showsAvatar {
      for constraint in avatarSizeConstraints {
        constraint.constant = MessageBubbleMetrics.avatarSize
      }
      senderAvatar.configure(event: event)
    }

    applyVerticalMetrics(content: content)
    updateBubbleWidths()
  }

  private func applyVerticalMetrics(content: MatrixRustSDK.MsgLikeContent) {
    let metrics = verticalMetrics(bubble: bubble, content: content)
    contentTopToRow.constant = metrics.contentTop
    contentTopToReply?.constant = metrics.replyGap
    contentBottomToRow.constant = -(metrics.contentBottom + metrics.time)
    threadTopConstraint?.constant = Self.threadSpacing + metrics.afterContent
    reactionsTopToContent?.constant = Self.reactionSpacing + metrics.afterContent
    receiptsTopToContent?.constant = Self.receiptSpacing + metrics.afterContent
    threadBottomConstraint?.constant = -(metrics.otherBottom + metrics.time)
    reactionsBottomToRow?.constant = -(metrics.otherBottom + metrics.time)
    receiptsBottomToRow?.constant = -(metrics.otherBottom + metrics.time)
  }

  /// Positions the column and shrinks the bubble to its content for the current row width.
  private func updateBubbleWidths() {
    guard let bubble, let currentContent, bounds.width > 0 else { return }
    let columnWidth = MessageBubbleMetrics.columnWidth(rowWidth: bounds.width, placement: bubble)
    let leading = MessageBubbleMetrics.columnLeading(rowWidth: bounds.width, placement: bubble)
    let contentWidth = bubbleContentWidth(for: currentContent, columnWidth: columnWidth)
    if guideWidthBubble.constant != columnWidth { guideWidthBubble.constant = columnWidth }
    if guideLeadingBubble.constant != leading { guideLeadingBubble.constant = leading }
    if contentWidthBubble.constant != contentWidth { contentWidthBubble.constant = contentWidth }
  }

  private func bubbleContentWidth(
    for content: MatrixRustSDK.MsgLikeContent, columnWidth: CGFloat
  ) -> CGFloat {
    let maxWidth = max(columnWidth - 2 * MessageBubbleMetrics.padding(for: contentKind).width, 1)
    if let cache = preferredWidthCache, cache.maxWidth == maxWidth {
      return cache.width
    }
    let width = min(contentView.preferredWidth(for: content, maxWidth: maxWidth), maxWidth)
    preferredWidthCache = (maxWidth, width)
    return width
  }

  private func updateBubbleColors() {
    guard let bubble else { return }
    effectiveAppearance.performAsCurrentDrawingAppearance {
      bubbleBackground.layer?.backgroundColor =
        MessageBubbleMetrics.backgroundColor(isOwn: bubble.isOwn).cgColor
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateBubbleColors()
  }

  /// The width available to the reply preview, thread summary and reactions.
  private func columnWidth(forRowWidth rowWidth: CGFloat) -> CGFloat {
    if let bubble {
      return MessageBubbleMetrics.columnWidth(rowWidth: rowWidth, placement: bubble)
    }
    return max(rowWidth - Self.contentHorizontalInset, 1)
  }

  private func configureThread(summary: MatrixRustSDK.ThreadSummary?, onClick: (() -> Void)?) {
    guard let summary else {
      threadSummaryView?.isHidden = true
      threadSummaryView?.onClick = nil
      threadTopConstraint?.isActive = false
      return
    }

    if threadSummaryView == nil {
      let view = MessageThreadSummaryView()
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: columnGuide.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: columnGuide.trailingAnchor),
      ])
      threadSummaryView = view
      threadHeightConstraint = view.heightAnchor.constraint(equalToConstant: 0)
      threadHeightConstraint?.isActive = true
      threadTopConstraint = view.topAnchor.constraint(
        equalTo: contentView.bottomAnchor, constant: Self.threadSpacing)
      threadBottomConstraint = view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
      threadBottomConstraint?.priority = .init(999)
      if let reactionsView {
        reactionsTopToThread = reactionsView.topAnchor.constraint(
          equalTo: view.bottomAnchor, constant: Self.reactionSpacing)
      }
      if let receiptsView {
        receiptsTopToThread = receiptsView.topAnchor.constraint(
          equalTo: view.bottomAnchor, constant: Self.receiptSpacing)
      }
    }

    threadSummaryView?.configure(summary: summary)
    threadSummaryView?.onClick = onClick
    threadSummaryView?.isHidden = false
    threadHeightConstraint?.constant = MessageThreadSummaryView.height(for: summary)
    threadTopConstraint?.isActive = true
  }

  private func configureReactions(
    _ reactions: [MatrixRustSDK.Reaction], ownUserId: String?, onClick: ((String) -> Void)?
  ) {
    self.reactions = reactions
    if !reactions.isEmpty, reactionsView == nil {
      let view = MessageReactionsView(frame: .zero)
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
      view.leadingAnchor.constraint(equalTo: columnGuide.leadingAnchor).isActive = true
      reactionsTrailingToContent = view.trailingAnchor.constraint(
        equalTo: columnGuide.trailingAnchor)
      reactionsView = view
      reactionsHeightConstraint = view.heightAnchor.constraint(equalToConstant: 0)
      reactionsHeightConstraint?.isActive = true
      reactionsTopToContent = view.topAnchor.constraint(
        equalTo: contentView.bottomAnchor, constant: Self.reactionSpacing)
      if let threadSummaryView {
        reactionsTopToThread = view.topAnchor.constraint(
          equalTo: threadSummaryView.bottomAnchor, constant: Self.reactionSpacing)
      }
      reactionsBottomToRow = view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
      reactionsBottomToRow?.priority = .init(999)
      if let receiptsView {
        receiptsTopToReactions = receiptsView.topAnchor.constraint(
          equalTo: view.topAnchor, constant: 5)
        reactionsTrailingToReceipts = view.trailingAnchor.constraint(
          equalTo: receiptsView.leadingAnchor, constant: -Self.receiptSpacing)
      }
    }

    reactionsView?.configure(reactions: reactions, ownUserId: ownUserId)
    reactionsView?.onReactionClick = onClick
    reactionsView?.isHidden = reactions.isEmpty

    reactionsTopToContent?.isActive = false
    reactionsTopToThread?.isActive = false

    if !reactions.isEmpty {
      (threadSummaryView?.isHidden == false ? reactionsTopToThread : reactionsTopToContent)?
        .isActive = true
      updateReactionsHeight()
    }
  }

  private func configureReceipts(
    _ receipts: [String: MatrixProtocols.Receipt], roomMembers: [MatrixRustSDK.RoomMember],
    imageLoader: MactrixUI.ImageLoader?, handleMatrixUri: ((MatrixUriScheme) -> Bool)?
  ) {
    if !receipts.isEmpty, receiptsView == nil {
      let view = MessageReadReceiptsView()
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
      receiptsView = view
      let heightConstraint = view.heightAnchor.constraint(
        equalToConstant: MessageReadReceiptsView.rowHeight)
      receiptsHeightConstraint = heightConstraint
      NSLayoutConstraint.activate([
        view.trailingAnchor.constraint(equalTo: columnGuide.trailingAnchor),
        heightConstraint,
      ])
      receiptsWidthConstraint = view.widthAnchor.constraint(equalToConstant: 0)
      receiptsWidthConstraint?.isActive = true
      receiptsTopToContent = view.topAnchor.constraint(
        equalTo: contentView.bottomAnchor, constant: Self.receiptSpacing)
      if let threadSummaryView {
        receiptsTopToThread = view.topAnchor.constraint(
          equalTo: threadSummaryView.bottomAnchor, constant: Self.receiptSpacing)
      }
      if let reactionsView {
        receiptsTopToReactions = view.topAnchor.constraint(
          equalTo: reactionsView.topAnchor, constant: 5)
        reactionsTrailingToReceipts = reactionsView.trailingAnchor.constraint(
          equalTo: view.leadingAnchor, constant: -Self.receiptSpacing)
      }
      receiptsBottomToRow = view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
      // NSTableView can briefly keep the old row height while configuring a reused view.
      receiptsBottomToRow?.priority = .init(999)
    }

    receiptsView?.isHidden = receipts.isEmpty
    receiptsView?.handleMatrixUri = handleMatrixUri
    if !receipts.isEmpty {
      receiptsView?.configure(receipts: receipts, members: roomMembers, imageLoader: imageLoader)
      receiptsWidthConstraint?.constant = MessageReadReceiptsView.width(for: receipts.count)
    }

    contentBottomToRow.isActive = false
    threadBottomConstraint?.isActive = false
    reactionsBottomToRow?.isActive = false
    receiptsTopToContent?.isActive = false
    receiptsTopToThread?.isActive = false
    receiptsTopToReactions?.isActive = false
    receiptsBottomToRow?.isActive = false
    let trailingConstraints = [reactionsTrailingToContent, reactionsTrailingToReceipts].compactMap {
      $0
    }
    NSLayoutConstraint.deactivate(trailingConstraints)
    (receipts.isEmpty || reactions.isEmpty
      ? reactionsTrailingToContent : reactionsTrailingToReceipts)?.isActive = true

    if receipts.isEmpty {
      if !reactions.isEmpty {
        reactionsBottomToRow?.isActive = true
      } else if threadSummaryView?.isHidden == false {
        threadBottomConstraint?.isActive = true
      } else {
        contentBottomToRow.isActive = true
      }
    } else {
      if !reactions.isEmpty {
        receiptsTopToReactions?.isActive = true
        reactionsBottomToRow?.isActive = true
      } else if threadSummaryView?.isHidden == false {
        receiptsTopToThread?.isActive = true
        receiptsBottomToRow?.isActive = true
      } else {
        receiptsTopToContent?.isActive = true
        receiptsBottomToRow?.isActive = true
      }
    }
    updateReactionsHeight()
  }

  func configureReply(details: MatrixRustSDK.EmbeddedEventDetails?, onClick: (() -> Void)?) {
    replyDetails = details
    guard let details else {
      replyPreview?.isHidden = true
      replyPreview?.onClick = nil
      contentTopToReply?.isActive = false
      contentTopToRow.isActive = true
      return
    }

    if replyPreview == nil {
      let preview = MessageReplyPreviewView()
      preview.translatesAutoresizingMaskIntoConstraints = false
      addSubview(preview)
      NSLayoutConstraint.activate([
        preview.leadingAnchor.constraint(equalTo: columnGuide.leadingAnchor),
        preview.trailingAnchor.constraint(equalTo: columnGuide.trailingAnchor),
        preview.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      ])
      replyPreview = preview
      replyHeightConstraint = preview.heightAnchor.constraint(equalToConstant: 28)
      replyHeightConstraint?.isActive = true
      contentTopToReply = contentView.topAnchor.constraint(
        equalTo: preview.bottomAnchor, constant: Self.replySpacing)
    }

    replyPreview?.configure(details: details)
    replyPreview?.onClick = onClick
    replyPreview?.isHidden = false
    contentTopToRow.isActive = false
    contentTopToReply?.isActive = true
    updateReplyHeight()
  }

  override func layout() {
    super.layout()
    updateBubbleWidths()
    updateReplyHeight()
    updateReactionsHeight()
    if bubble != nil {
      let radius = min(MessageBubbleMetrics.cornerRadius, bubbleBackground.bounds.height / 2)
      if bubbleBackground.layer?.cornerRadius != radius {
        bubbleBackground.layer?.cornerRadius = radius
      }
    }
  }

  private func updateReplyHeight() {
    guard let replyDetails, bounds.width > 0 else { return }
    let height = MessageReplyPreviewView.height(
      for: replyDetails, width: columnWidth(forRowWidth: bounds.width))
    if replyHeightConstraint?.constant != height {
      replyHeightConstraint?.constant = height
    }
  }

  private func updateReactionsHeight() {
    guard !reactions.isEmpty, bounds.width > 0 else { return }
    let receiptWidth =
      receiptsView?.isHidden == false
      ? MessageReadReceiptsView.width(for: receiptsView?.receiptCount ?? 0) + Self.receiptSpacing
      : 0
    let height = MessageReactionsView.height(
      for: reactions, width: max(columnWidth(forRowWidth: bounds.width) - receiptWidth, 1))
    if reactionsHeightConstraint?.constant != height {
      reactionsHeightConstraint?.constant = height
    }
  }

  override func mouseEntered(with event: NSEvent) {
    if onHoverChange?(self, true, event) ?? true {
      setHoverHighlight(true)
    }
  }

  override func mouseDown(with event: NSEvent) {
    onSelectRequest?(self)
    super.mouseDown(with: event)
  }

  override func mouseExited(with event: NSEvent) {
    setHoverHighlight(onHoverChange?(self, false, event) ?? false)
  }

  func setHoverHighlight(_ highlighted: Bool) {
    isHovered = highlighted
    updateBackground()
  }

  func setSelected(_ selected: Bool) {
    isMessageSelected = selected
    updateBackground()
  }

  private func updateBackground() {
    if isMessageSelected {
      layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
    } else {
      layer?.backgroundColor = isHovered ? .init(gray: 0.5, alpha: 0.1) : nil
    }
  }

  private static func hasBeenEdited(_ content: MatrixRustSDK.MsgLikeContent) -> Bool {
    switch content.kind {
    case .message(let message): return message.isEdited
    case .poll(_, _, _, _, _, _, let hasBeenEdited): return hasBeenEdited
    default: return false
    }
  }

  func height(
    for content: MatrixRustSDK.MsgLikeContent, width: CGFloat,
    replyDetails: MatrixRustSDK.EmbeddedEventDetails?, reactions: [MatrixRustSDK.Reaction],
    receiptCount: Int, bubble: MessageBubblePlacement? = nil
  ) -> CGFloat {
    if let bubble {
      return bubbleHeight(
        for: content, width: width, replyDetails: replyDetails, reactions: reactions,
        receiptCount: receiptCount, bubble: bubble)
    }
    let contentWidth = max(width - Self.contentHorizontalInset, 1)
    let replyHeight =
      replyDetails.map {
        MessageReplyPreviewView.height(for: $0, width: contentWidth) + Self.replySpacing
      } ?? 0
    let threadHeight =
      content.threadSummary.map {
        MessageThreadSummaryView.height(for: $0) + Self.threadSpacing
      } ?? 0
    let availableReactionWidth =
      contentWidth
      - (receiptCount > 0
        ? MessageReadReceiptsView.width(for: receiptCount) + Self.receiptSpacing : 0)
    let reactionsHeight =
      reactions.isEmpty
      ? 0
      : MessageReactionsView.height(for: reactions, width: max(availableReactionWidth, 1))
        + Self.reactionSpacing
    let receiptsHeight =
      receiptCount == 0 || !reactions.isEmpty
      ? 0 : MessageReadReceiptsView.rowHeight + Self.receiptSpacing
    return max(
      ceil(contentView.height(for: content, width: contentWidth)) + replyHeight + threadHeight
        + reactionsHeight + receiptsHeight + 8,
      max(
        Self.hasBeenEdited(content) ? 40 : 28,
        6 + ceil(timestamp.font?.boundingRectForFont.height ?? 0)
          + (Self.hasBeenEdited(content)
            ? 1 + ceil(editedLabel.font?.boundingRectForFont.height ?? 0) : 0)))
  }

  /// Mirrors the bubble layout's vertical constraints; see `applyVerticalMetrics`.
  private func bubbleHeight(
    for content: MatrixRustSDK.MsgLikeContent, width: CGFloat,
    replyDetails: MatrixRustSDK.EmbeddedEventDetails?, reactions: [MatrixRustSDK.Reaction],
    receiptCount: Int, bubble: MessageBubblePlacement
  ) -> CGFloat {
    let metrics = verticalMetrics(bubble: bubble, content: content)
    let columnWidth = MessageBubbleMetrics.columnWidth(rowWidth: width, placement: bubble)
    preferredWidthCache = nil
    let contentWidth = bubbleContentWidth(for: content, columnWidth: columnWidth)

    var height: CGFloat = 0
    if let replyDetails {
      height +=
        4 + MessageReplyPreviewView.height(for: replyDetails, width: columnWidth)
        + metrics.replyGap
    } else {
      height += metrics.contentTop
    }
    height += ceil(contentView.height(for: content, width: contentWidth))

    let hasThread = content.threadSummary != nil
    if let summary = content.threadSummary {
      height +=
        Self.threadSpacing + metrics.afterContent
        + MessageThreadSummaryView.height(for: summary)
    }
    if !reactions.isEmpty {
      let receiptsWidth =
        receiptCount > 0
        ? MessageReadReceiptsView.width(for: receiptCount) + Self.receiptSpacing : 0
      height += Self.reactionSpacing + (hasThread ? 0 : metrics.afterContent)
      height += MessageReactionsView.height(
        for: reactions, width: max(columnWidth - receiptsWidth, 1))
    } else if receiptCount > 0 {
      height += Self.receiptSpacing + (hasThread ? 0 : metrics.afterContent)
      height += MessageReadReceiptsView.rowHeight
    }

    let contentIsLast = !hasThread && reactions.isEmpty && receiptCount == 0
    height += (contentIsLast ? metrics.contentBottom : metrics.otherBottom) + metrics.time
    if bubble.showsAvatar {
      height = max(height, MessageBubbleMetrics.avatarSize + metrics.contentBottom + metrics.time)
    }
    return ceil(height)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
