import Foundation

/// The type of reaction on an iMessage.
/// Values correspond to the `associated_message_type` column in the Messages database.
public enum ReactionType: Int, Sendable, Equatable, CaseIterable {
  case love = 2000
  case like = 2001
  case dislike = 2002
  case laugh = 2003
  case emphasis = 2004
  case question = 2005

  /// Returns the reaction type for a removal (values 3000-3005)
  public static func fromRemoval(_ value: Int) -> ReactionType? {
    return ReactionType(rawValue: value - 1000)
  }

  /// Whether this associated_message_type represents adding a reaction (2000-2005)
  public static func isReactionAdd(_ value: Int) -> Bool {
    return value >= 2000 && value <= 2005
  }

  /// Whether this associated_message_type represents removing a reaction (3000-3005)
  public static func isReactionRemove(_ value: Int) -> Bool {
    return value >= 3000 && value <= 3005
  }

  /// Human-readable name for the reaction
  public var name: String {
    switch self {
    case .love: return "love"
    case .like: return "like"
    case .dislike: return "dislike"
    case .laugh: return "laugh"
    case .emphasis: return "emphasis"
    case .question: return "question"
    }
  }

  /// Emoji representation of the reaction
  public var emoji: String {
    switch self {
    case .love: return "❤️"
    case .like: return "👍"
    case .dislike: return "👎"
    case .laugh: return "😂"
    case .emphasis: return "‼️"
    case .question: return "❓"
    }
  }
}

/// A reaction to an iMessage.
public struct Reaction: Sendable, Equatable {
  /// The ROWID of the reaction message in the database
  public let rowID: Int64
  /// The type of reaction
  public let reactionType: ReactionType
  /// The sender of the reaction (phone number or email)
  public let sender: String
  /// Whether the reaction was sent by the current user
  public let isFromMe: Bool
  /// When the reaction was added
  public let date: Date
  /// The ROWID of the message being reacted to
  public let associatedMessageID: Int64

  public init(
    rowID: Int64,
    reactionType: ReactionType,
    sender: String,
    isFromMe: Bool,
    date: Date,
    associatedMessageID: Int64
  ) {
    self.rowID = rowID
    self.reactionType = reactionType
    self.sender = sender
    self.isFromMe = isFromMe
    self.date = date
    self.associatedMessageID = associatedMessageID
  }
}

public struct Chat: Sendable, Equatable {
  public let id: Int64
  public let identifier: String
  public let name: String
  public let service: String
  public let lastMessageAt: Date

  public init(id: Int64, identifier: String, name: String, service: String, lastMessageAt: Date) {
    self.id = id
    self.identifier = identifier
    self.name = name
    self.service = service
    self.lastMessageAt = lastMessageAt
  }
}

public struct Message: Sendable, Equatable {
  public let rowID: Int64
  public let chatID: Int64
  public let sender: String
  public let text: String
  public let date: Date
  public let isFromMe: Bool
  public let service: String
  public let handleID: Int64?
  public let attachmentsCount: Int

  public init(
    rowID: Int64,
    chatID: Int64,
    sender: String,
    text: String,
    date: Date,
    isFromMe: Bool,
    service: String,
    handleID: Int64?,
    attachmentsCount: Int
  ) {
    self.rowID = rowID
    self.chatID = chatID
    self.sender = sender
    self.text = text
    self.date = date
    self.isFromMe = isFromMe
    self.service = service
    self.handleID = handleID
    self.attachmentsCount = attachmentsCount
  }
}

public struct AttachmentMeta: Sendable, Equatable {
  public let filename: String
  public let transferName: String
  public let uti: String
  public let mimeType: String
  public let totalBytes: Int64
  public let isSticker: Bool
  public let originalPath: String
  public let missing: Bool

  public init(
    filename: String,
    transferName: String,
    uti: String,
    mimeType: String,
    totalBytes: Int64,
    isSticker: Bool,
    originalPath: String,
    missing: Bool
  ) {
    self.filename = filename
    self.transferName = transferName
    self.uti = uti
    self.mimeType = mimeType
    self.totalBytes = totalBytes
    self.isSticker = isSticker
    self.originalPath = originalPath
    self.missing = missing
  }
}
