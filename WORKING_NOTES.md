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

### Unit 1: attributedBody Research (2026-01-28)

#### How does iMessage store formatted text?

iMessage stores formatted message content in the `attributedBody` BLOB column of `chat.db`. This column contains a serialized `NSMutableAttributedString` encoded using Apple's **typedstream** format (NOT binary plist as initially assumed).

**Format identification:**
```
$ file attributedBody.blob
sample: NeXT/Apple typedstream data, little endian, version 4, system 1000
```

The typedstream format is a binary serialization protocol from NeXTSTEP, used by `NSArchiver`/`NSUnarchiver` (NOT `NSKeyedArchiver`). It's undocumented and specific to Apple's Foundation implementation.

#### typedstream Format Structure

The attributedBody follows this general pattern:
```
streamtypedè@NSMutableAttributedStringNSAttributedStringNSObject
NSMutableStringNSString+-[THE TEXT MESSAGE]iI-
NSDictionaryi__kIMMessagePartAttributeNameNSNumberNSValue*
```

**Key structural elements:**
- Header: version byte (0x04), "streamtyped" literal, system info (0x81 e8 03 = 1000)
- 0x84: Starts a data blob; following byte indicates length
- 0x85: Ends class inheritance chains
- 0x86: Ends data blobs
- 0x81: Precedes 16-bit integers
- 0x92+: References to cached archivable objects

**String encoding:**
- Text follows a type tag (`+` for UTF-8) and length byte
- Length byte before text: single byte if < 0x81, two bytes (little-endian) if starts with 0x81

#### How are formatting attributes stored?

The `attributedBody` uses NSDictionary structures with range information. Based on BlueBubbles documentation, the structure is:

```json
{
  "string": "message text",
  "runs": [{
    "range": [startIndex, length],  // NOT [start, end]!
    "attributes": {
      "__kIMMessagePartAttributeName": 0,
      "__kIMMentionConfirmedMention": "contact_address"
    }
  }]
}
```

**Known attribute keys (private API):**
- `__kIMMessagePartAttributeName` — Part index for multi-part messages
- `__kIMMentionConfirmedMention` — @mention data
- iOS 18+ likely added: text formatting attributes for bold/italic/underline/strikethrough
- iOS 18+ text effects: Big, Small, Shake, Nod, Explode, Ripple, Bloom, Jitter

**Critical note:** The specific attribute keys for bold/italic/underline (`__kIMTextBoldAttribute`, etc.) are NOT publicly documented. These are private API constants in Apple's IMCore/IMFoundation frameworks.

#### iOS 18 Text Formatting (September 2024)

iOS 18/iPadOS 18/macOS Sequoia introduced native iMessage formatting:
- **Bold** (Cmd+B)
- **Italic** (Cmd+I)
- **Underline** (Cmd+U)
- **Strikethrough** (Cmd+S)
- **Text Effects**: Big, Small, Shake, Nod, Explode, Ripple, Bloom, Jitter

**Compatibility requirement:** Both sender AND receiver must be on iOS 18+/macOS Sequoia+. Older versions see plain text.

#### Can Swift encode typedstream without private APIs?

**Short answer: NO — not feasibly.**

**Reasons:**
1. `NSArchiver` (which produces typedstream) is **deprecated** since macOS 10.13 and **never available on iOS**
2. The typedstream format is **undocumented** — only discoverable via reverse engineering
3. Apple's modern archiver is `NSKeyedArchiver` which produces binary plist, NOT typedstream
4. Writing typedstream from scratch would require reimplementing Apple's proprietary serialization

**The fundamental problem:**
- iMessage's `attributedBody` expects typedstream format
- Swift/public APIs only provide `NSKeyedArchiver` (binary plist)
- There's no public API to produce typedstream-format data

#### Alternative approaches investigated

1. **AppleScript** — Cannot send styled/formatted text. The Messages.app scripting dictionary doesn't expose text formatting properties. Only plain text strings can be sent.

2. **Private APIs (requires SIP disabled):**
   - **BlueBubbles Private API** — Hooks into IMCore to send tapbacks and typing indicators. Requires disabling System Integrity Protection. Does support mentions via attributedBody.
   - **Barcelona** (beeper/barcelona) — Swift framework that interfaces with Apple's private IM frameworks via reverse engineering. Used by mautrix-imessage bridge. Requires SIP disabled.

3. **Direct database writes** — NOT possible. Messages.app reads from chat.db but doesn't re-read it for sending. Writing to the DB wouldn't trigger a send.

#### Existing Libraries/Tools

**For READING attributedBody:**

| Library | Language | Notes |
|---------|----------|-------|
| [crabstep](https://github.com/ReagentX/crabstep) | Rust | Pure Rust typedstream deserializer |
| [imessage-database](https://github.com/ReagentX/imessage-exporter) | Rust | Full iMessage DB parser, uses crabstep |
| [python-typedstream](https://github.com/dgelessus/python-typedstream) | Python | Cross-platform typedstream reader |
| imsg's TypedStreamParser.swift | Swift | Already in this project |

**For SENDING with private APIs (SIP disabled):**

| Library | Language | Notes |
|---------|----------|-------|
| [BlueBubbles Helper](https://github.com/BlueBubblesApp/bluebubbles-helper) | Obj-C | Hooks IMCore, supports tapbacks/mentions |
| [Barcelona](https://github.com/beeper/barcelona) | Swift | Full iMessage framework, used by Beeper |

**For SENDING (public APIs only):**

| Library | Language | Notes |
|---------|----------|-------|
| [imessage-kit](https://github.com/photon-hq/imessage-kit) | TypeScript | AppleScript-based, plain text only |

#### Key Findings Summary

1. **attributedBody encoding is NOT feasible in pure Swift** without private APIs
2. **iMessage expects typedstream format** which cannot be produced by public Swift APIs
3. **NSArchiver is deprecated/unavailable** — modern `NSKeyedArchiver` produces incompatible format
4. **iOS 18 added formatting** but the attribute keys are private/undocumented
5. **Private API solutions exist** (BlueBubbles, Barcelona) but require SIP disabled
6. **AppleScript cannot send formatted text** — only plain text strings

#### Recommended Approach for imsg

Given the constraints, the options are:

**Option A: Accept plain text only (recommended for now)**
- Continue using AppleScript for sending
- Focus on READING formatted text from attributedBody (already works)
- Document that sending formatted text is not supported

**Option B: Markdown-style syntax (user-facing only)**
- Accept `**bold**`, `*italic*`, `` `code` `` in CLI input
- Store/display with markers, but send as plain text
- Receiver sees the markers (like Discord/Slack without rendering)

**Option C: Private API integration (requires SIP disabled)**
- Integrate BlueBubbles helper or Barcelona
- Would enable full formatting AND tapback sending
- Significant complexity, security implications, maintenance burden

**Option D: Wait for Apple**
- Apple may eventually expose formatting APIs publicly
- iOS 18 is the first version with formatting; APIs might evolve

## Decisions

**2026-01-28:** Based on Unit 1 research, sending formatted text via public APIs is not feasible. The attributedBody uses undocumented typedstream format that cannot be produced without private APIs.

## Next Steps

1. ~~Research rich text formatting in iMessage (attributedBody field)~~ ✅ Done
2. Research how to send tapbacks via AppleScript or other APIs
3. Decide on approach for formatting (Option A/B/C/D above)
4. Plan implementation approach for sending tapbacks
