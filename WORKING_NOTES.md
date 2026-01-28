# imsg Formatting + Tapbacks — Working Notes

## Project Goal
Add rich text formatting (bold/italic/monospace) and tapback/reaction support to imsg CLI.

## Key Files (to explore)
- `Sources/IMsgCore/MessageStore.swift` — likely where DB queries happen
- `Sources/IMsgCore/Models.swift` — data models
- `Sources/imsg/Commands/` — CLI command handlers

## Upstream Branch
`claude/imessage-reaction-detection-8hlOR` has existing tapback work:
- feat: add iMessage reaction detection support
- enhancement: add tapback reaction detection query + custom emoji
- fix: harden reaction detection

## Research Findings

### Unit 0 Exploration (2026-01-28)

#### Does the upstream reaction branch compile and work?
- **Compiles**: Yes, `swift build` succeeds on both main and the upstream branch
- **Tests**: Tests fail to compile due to `import Testing` (Swift Testing framework) not being available. This is a toolchain issue, not a code issue. The test file `MessageStoreReactionsTests.swift` uses the newer `@Test` macro syntax.

#### Does it cover sending tapbacks or just receiving?
- **Receiving only**: The upstream branch only covers READING/DETECTING reactions, NOT sending them.
- The `MessageStore.reactions(for:)` method queries the database for reactions on a given message.
- No changes to `MessageSender.swift` — it still only sends text/attachments.

#### Where is message reading/writing handled?

**Reading (Database queries):**
- `Sources/IMsgCore/MessageStore.swift` — Main store class, handles DB connection, chat listing, reactions
- `Sources/IMsgCore/MessageStore+Messages.swift` — Message fetching: `messages(chatID:limit:filter:)`, `messagesAfter(afterRowID:chatID:limit:)`
- `Sources/IMsgCore/MessageStore+Helpers.swift` — Helper methods (type conversion, date handling)
- Messages are read from SQLite database at `~/Library/Messages/chat.db`

**Writing (Sending messages):**
- `Sources/IMsgCore/MessageSender.swift` — Uses AppleScript to send messages via Messages.app
- `MessageSendOptions` struct holds: recipient, text, attachmentPath, service, region, chatIdentifier, chatGUID
- Sends via AppleScript: `tell application "Messages" send theMessage to targetChat`
- Falls back to `osascript` CLI if NSAppleScript fails

**CLI Commands:**
- `Sources/imsg/Commands/SendCommand.swift` — `imsg send --to X --text "Y"`
- `Sources/imsg/Commands/HistoryCommand.swift` — `imsg history --chat-id N --limit M`
- `Sources/imsg/Commands/WatchCommand.swift` — `imsg watch --chat-id N` (streams new messages)
- `Sources/imsg/Commands/ChatsCommand.swift` — `imsg chats` (list chats)

#### What's the overall architecture?

```
┌──────────────────────────────────────────────────────────────────┐
│                         CLI (imsg)                               │
├──────────────────────────────────────────────────────────────────┤
│  Commands/           OutputModels.swift    RuntimeOptions.swift  │
│  - ChatsCommand      - ChatPayload         - JSON mode flag      │
│  - HistoryCommand    - MessagePayload                            │
│  - SendCommand       - ReactionPayload                           │
│  - WatchCommand      - AttachmentPayload                         │
└───────────────────────────────┬──────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────┐
│                      IMsgCore Library                            │
├──────────────────────────────────────────────────────────────────┤
│  MessageStore.swift     MessageSender.swift    Models.swift      │
│  - listChats()          - send(options)        - Chat            │
│  - messages()           - AppleScript based    - Message         │
│  - messagesAfter()                             - Reaction        │
│  - reactions()                                 - ReactionType    │
│  - attachments()                               - AttachmentMeta  │
│                                                                  │
│  MessageWatcher.swift   TypedStreamParser.swift                  │
│  - stream() for watch   - Parse attributedBody                   │
└───────────────────────────────┬──────────────────────────────────┘
                                │
        ┌───────────────────────┴───────────────────────┐
        ▼                                               ▼
┌───────────────────┐                         ┌─────────────────────┐
│  chat.db (SQLite) │                         │   Messages.app      │
│  ~/Library/       │                         │   (via AppleScript) │
│  Messages/chat.db │                         │                     │
│  READ ONLY        │                         │   WRITE ONLY        │
└───────────────────┘                         └─────────────────────┘
```

#### Reaction Data Model (from upstream branch, now on main)

```swift
public enum ReactionType: Sendable, Equatable, Hashable {
  case love      // 2000, ❤️
  case like      // 2001, 👍
  case dislike   // 2002, 👎
  case laugh     // 2003, 😂
  case emphasis  // 2004, ‼️
  case question  // 2005, ❓
  case custom(String)  // 2006, custom emoji
}

public struct Reaction: Sendable, Equatable {
  public let rowID: Int64
  public let reactionType: ReactionType
  public let sender: String
  public let isFromMe: Bool
  public let date: Date
  public let associatedMessageID: Int64
}
```

- Reactions in DB: `associated_message_type` 2000-2006 (add), 3000-3006 (remove)
- Reference original message via `associated_message_guid` with format `p:X/GUID`

#### Current capabilities summary

| Feature | Status | Notes |
|---------|--------|-------|
| Read messages | ✅ | Via SQLite |
| Send messages | ✅ | Via AppleScript |
| Read attachments | ✅ | Via SQLite |
| Send attachments | ✅ | Via AppleScript |
| Read reactions | ✅ | Via SQLite (upstream merged) |
| Send reactions | ❌ | Not implemented |
| Rich text formatting | ❌ | Not implemented |

## Decisions

(To be filled in as work progresses)

## Next Steps

1. Research how to send tapbacks via AppleScript or other APIs
2. Research rich text formatting in iMessage (attributedBody field)
3. Plan implementation approach for sending tapbacks
