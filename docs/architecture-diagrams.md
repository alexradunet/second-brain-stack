# Nazar Second Brain - Infrastructure Diagrams

Complete visual documentation of the system architecture, data flows, and synchronization mechanisms.

---

## 1. High-Level System Architecture

```mermaid
flowchart TB
    subgraph Internet["Internet (No Direct Access)"]
        direction TB
        ATTACKERS["Attackers/Scanners"]
        NOTE1["SSH Port 22: Closed to public<br/>HTTPS Port 443: No public IP"]
    end

    subgraph TailscaleNET["Tailscale VPN Mesh Network (100.x.x.x)"]
        direction TB

        subgraph VPS["VPS (Debian 13)"]
            direction TB

            subgraph Services["systemd User Services (nazar)"]
                OPENCLAW["OpenClaw Gateway<br/>(Node.js 22 + Voice Tools)"]
                SYNCTHING["Syncthing<br/>(Real-time P2P Sync)"]
            end

            VAULT[("Vault<br/>/home/nazar/vault")]
            CONFIG[("Config<br/>/home/nazar/.openclaw")]

            UFW["UFW Firewall<br/>(Tailscale only)"]
            FAIL2BAN["Fail2Ban"]
            TSD["Tailscale Daemon"]
        end

        subgraph LocalDevices["User Devices"]
            LAPTOP["Laptop (Windows)<br/>Obsidian + Syncthing"]
            PHONE["Phone (Android)<br/>Obsidian + Syncthing"]
        end
    end

    %% Connections
    LAPTOP <-->|"Syncthing P2P<br/>(via Tailscale)"| SYNCTHING
    PHONE <-->|"Syncthing P2P<br/>(via Tailscale)"| SYNCTHING

    SYNCTHING <-->|"Real-time sync"| VAULT
    VAULT <-->|"Reads/Writes"| OPENCLAW

    TSD <-->|"Serves"| OPENCLAW

    UFW -.->|"Blocks"| Internet
    FAIL2BAN -.->|"Bans brute-force"| Internet

    LAPTOP -.->|"HTTPS via Tailscale"| OPENCLAW
    PHONE -.->|"HTTPS via Tailscale"| OPENCLAW

    style Internet fill:#ffcccc
    style TailscaleNET fill:#ccffcc
    style VPS fill:#e6f3ff
    style Services fill:#fff4e6
```

---

## 2. Syncthing Synchronization Flow (Detailed)

```mermaid
sequenceDiagram
    autonumber
    participant LAPTOP as Laptop<br/>Obsidian + Syncthing
    participant PHONE as Phone<br/>Obsidian + Syncthing
    participant ST_VPS as Syncthing<br/>(VPS)
    participant VAULT as Vault<br/>(/home/nazar/vault)
    participant AGENT as Nazar Agent
    participant GATEWAY as OpenClaw<br/>Gateway

    Note over LAPTOP,GATEWAY: User Creates Note on Laptop
    LAPTOP->>LAPTOP: Save note in Obsidian
    LAPTOP->>ST_VPS: Syncthing detects change, syncs via Tailscale
    activate ST_VPS
    ST_VPS->>VAULT: Write synced file
    VAULT-->>GATEWAY: File available to agent
    deactivate ST_VPS

    Note over PHONE,GATEWAY: Phone Gets Changes (real-time)
    ST_VPS->>PHONE: Syncthing pushes change via Tailscale
    PHONE->>PHONE: Obsidian refreshes

    Note over AGENT,GATEWAY: Agent Creates Daily Note
    GATEWAY->>AGENT: Process voice note
    AGENT->>VAULT: Write to daily note
    VAULT->>VAULT: File changed on disk

    Note over ST_VPS: Syncthing detects agent write
    ST_VPS->>LAPTOP: Sync new content via Tailscale
    ST_VPS->>PHONE: Sync new content via Tailscale
    LAPTOP->>LAPTOP: Obsidian refreshes
    PHONE->>PHONE: Obsidian refreshes
```

---

## 3. Data Flow Architecture

```mermaid
flowchart LR
    subgraph INPUTS["INPUT SOURCES"]
        VOICE["Voice Messages<br/>(WhatsApp/Telegram)"]
        MANUAL["Manual Notes<br/>(Obsidian)"]
        CLI["CLI Commands<br/>(SSH)"]
    end

    subgraph PROCESSING["PROCESSING LAYER"]
        OPENCLAW["OpenClaw Gateway"]
        WHISPER["Whisper STT<br/>Speech-to-Text"]
        PIPER["Piper TTS<br/>Text-to-Speech"]
        AI["LLM (Moonshot/<br/>Anthropic/OpenAI)"]
    end

    subgraph STORAGE["STORAGE LAYER"]
        subgraph VAULT["Vault (Syncthing)"]
            INBOX["00-inbox/<br/>Quick Capture"]
            DAILY["01-daily-journey/<br/>YYYY/MM-MMMM/YYYY-MM-DD.md"]
            PROJECTS["02-projects/<br/>Active Projects"]
            AREAS["03-areas/<br/>Life Areas"]
            RESOURCES["04-resources/<br/>Reference"]
            ARCHIVE["05-archive/<br/>Completed"]
            SYSTEM["99-system/<br/>Agent Workspace"]
        end
    end

    subgraph OUTPUTS["OUTPUT DESTINATIONS"]
        SYNC["Syncthing P2P<br/>(All Devices)"]
        VOICE_RESP["Voice Responses"]
        DASHBOARD["Control UI<br/>(Web Interface)"]
    end

    %% Input Flows
    VOICE -->|"Audio file"| WHISPER
    WHISPER -->|"Transcribed text"| OPENCLAW
    MANUAL -->|"Direct edit"| VAULT
    CLI -->|"openclaw commands"| OPENCLAW

    %% Processing
    OPENCLAW -->|"Process & analyze"| AI
    AI -->|"Generate response"| OPENCLAW
    OPENCLAW -->|"Synthesize speech"| PIPER

    %% Storage
    OPENCLAW -->|"Write daily notes,<br/>append voice transcriptions"| DAILY
    OPENCLAW -->|"Update workspace<br/>memory, tools"| SYSTEM

    %% Output Flows
    VAULT -->|"Syncthing sync"| SYNC
    PIPER -->|"Audio response"| VOICE_RESP
    OPENCLAW -->|"Web UI"| DASHBOARD

    style PROCESSING fill:#e6f3ff
    style STORAGE fill:#fff4e6
    style SYSTEM fill:#ffe6e6
```

---

## 4. Syncthing Sync Topology

```mermaid
graph TB
    subgraph LEGEND["Legend"]
        direction LR
        L1["Device with Syncthing"]
        L2["Tailscale VPN tunnel"]
        L3["Real-time bidirectional sync"]
    end

    subgraph SYNC_ARCH["Syncthing P2P Architecture"]
        direction TB

        subgraph LOCAL1["Laptop (Windows)"]
            WC1["Vault Folder<br/>C:/Obsidian/vault"]
            ST1["Syncthing"]
        end

        subgraph LOCAL2["Phone (Android)"]
            WC2["Vault Folder<br/>~/Obsidian/vault"]
            ST2["Syncthing"]
        end

        subgraph VPS_ST["VPS (Debian 13)"]
            ST_VPS["Syncthing<br/>(systemd user service)"]
            VAULT["Vault<br/>/home/nazar/vault"]
            OPENCLAW["OpenClaw<br/>(systemd user service)"]
        end
    end

    %% Sync flows (all over Tailscale)
    ST1 <===>|"Tailscale VPN<br/>Real-time sync"| ST_VPS
    ST2 <===>|"Tailscale VPN<br/>Real-time sync"| ST_VPS
    ST1 <===>|"Tailscale VPN<br/>Direct sync"| ST2

    %% Local connections
    WC1 <--> ST1
    WC2 <--> ST2
    ST_VPS <--> VAULT
    VAULT <--> OPENCLAW

    style VPS_ST fill:#e6f3ff
    style ST_VPS fill:#e6ffe6
    style OPENCLAW fill:#fff4e6
```

---

## 5. Security Architecture (Defense in Depth)

```mermaid
flowchart TB
    subgraph ATTACKER["Attacker"]
        PORT_SCAN["Port Scan<br/>(22, 443, etc.)"]
        BRUTE_FORCE["SSH Brute Force"]
        MITM["Man-in-the-Middle"]
    end

    subgraph LAYER1["Layer 1: Network"]
        TAILSCALE["Tailscale VPN<br/>WireGuard Encryption"]
        UFW["UFW Firewall<br/>Deny all incoming"]
        NOTE1["SSH: Only Tailscale<br/>HTTPS: Only Tailscale"]
    end

    subgraph LAYER2["Layer 2: Authentication"]
        SSH_KEYS["SSH Key-Only<br/>(No passwords)"]
        GATEWAY_TOKEN["Gateway Token Auth"]
        DEVICE_PAIRING["Device Pairing<br/>Approval required"]
    end

    subgraph LAYER3["Layer 3: User Isolation"]
        NAZAR_USER["nazar service user<br/>(no sudo, locked password)"]
        HOME_700["Home dir: mode 700"]
        SYSTEMD_SANDBOX["systemd sandboxing<br/>(NoNewPrivileges, ProtectSystem)"]
    end

    subgraph LAYER4["Layer 4: Agent Sandbox"]
        SANDBOX["Sandbox Mode<br/>'non-main' sessions"]
        READ_WRITE["ReadWritePaths:<br/>vault + .openclaw only"]
    end

    subgraph LAYER5["Layer 5: Secrets"]
        CONFIG_DIR["openclaw.json<br/>(mode 700 directory)"]
        NEVER_IN_VAULT["Never commit secrets<br/>to vault"]
    end

    subgraph LAYER6["Layer 6: Auto-Patching"]
        UNATTENDED["Unattended Upgrades<br/>(Security patches)"]
        FAIL2BAN["Fail2Ban<br/>(Bans attackers)"]
    end

    subgraph ASSETS["Protected Assets"]
        VPS["/home/nazar/"]
        VAULT["Vault Data"]
        GATEWAY["Gateway"]
    end

    %% Attack flows (blocked)
    PORT_SCAN -->|"Blocked"| UFW
    BRUTE_FORCE -->|"Blocked"| UFW
    BRUTE_FORCE -->|"Bans IP"| FAIL2BAN
    MITM -->|"Encrypted"| TAILSCALE

    %% Defense layers
    UFW --> TAILSCALE
    TAILSCALE --> SSH_KEYS
    SSH_KEYS --> GATEWAY_TOKEN
    GATEWAY_TOKEN --> DEVICE_PAIRING
    DEVICE_PAIRING --> NAZAR_USER
    NAZAR_USER --> SANDBOX
    SANDBOX --> CONFIG_DIR
    CONFIG_DIR --> UNATTENDED

    %% Protection
    UNATTENDED --> VPS
    FAIL2BAN --> VPS
    NAZAR_USER --> GATEWAY
    SANDBOX --> GATEWAY
    CONFIG_DIR --> VAULT

    style ATTACKER fill:#ffcccc
    style ASSETS fill:#ccffcc
    style LAYER1 fill:#e6f3ff
    style LAYER2 fill:#e6f3ff
    style LAYER3 fill:#e6f3ff
    style LAYER4 fill:#e6f3ff
    style LAYER5 fill:#e6f3ff
    style LAYER6 fill:#e6f3ff
```

---

## 6. Request Flow Example (Voice Note Processing)

```mermaid
sequenceDiagram
    autonumber
    actor USER as User
    participant PHONE as Phone (WhatsApp)
    participant GATEWAY as OpenClaw Gateway
    participant WHISPER as Whisper (STT)
    participant AI as LLM
    participant VAULT as Vault
    participant ST_VPS as Syncthing (VPS)
    participant LAPTOP as Laptop (Obsidian)

    USER->>PHONE: Send voice message
    PHONE->>GATEWAY: Webhook with audio

    GATEWAY->>WHISPER: Transcribe audio
    WHISPER-->>GATEWAY: "Meeting at 3pm tomorrow"

    GATEWAY->>AI: Analyze + extract insights
    AI-->>GATEWAY: Summary + action items

    GATEWAY->>VAULT: Append to daily note<br/>01-daily-journey/2026/02-February/2026-02-11.md
    Note right of VAULT: ---<br/>**[14:32]**<br/><br/>Meeting at 3pm tomorrow<br/><br/>_Nazar: Added to calendar_<br/>---

    GATEWAY-->>PHONE: Text confirmation

    Note over ST_VPS: Syncthing detects file change
    ST_VPS->>LAPTOP: Sync via Tailscale (real-time)

    LAPTOP->>LAPTOP: Obsidian renders updated note
    USER->>LAPTOP: Read and edit note

    Note over LAPTOP: User edits note
    LAPTOP->>ST_VPS: Syncthing syncs edit back to VPS
    ST_VPS->>VAULT: Updated file on disk
```

---

## 7. Directory Structure (Tree View)

```mermaid
graph TD
    ROOT["/home/nazar"]

    ROOT --> VAULT["vault/"]
    ROOT --> OPENCLAW_DIR[".openclaw/"]
    ROOT --> LOCAL[".local/"]

    %% Vault - PARA
    VAULT --> INBOX["00-inbox/"]
    VAULT --> DAILY["01-daily-journey/<br/>2026/02-February/"]
    VAULT --> PROJECTS["02-projects/"]
    VAULT --> AREAS["03-areas/"]
    VAULT --> RESOURCES["04-resources/"]
    VAULT --> ARCHIVE["05-archive/"]
    VAULT --> SYSTEM["99-system/"]
    VAULT --> OBSIDIAN[".obsidian/"]

    %% Daily notes example
    DAILY --> DAILY_FILE["2026-02-11.md"]

    %% System folder
    SYSTEM --> SYS_OPENCLAW["openclaw/"]
    SYSTEM --> TEMPLATES["templates/"]

    SYS_OPENCLAW --> WORKSPACE["workspace/"]
    SYS_OPENCLAW --> SKILLS["skills/"]
    SYS_OPENCLAW --> DOCS["docs/"]

    WORKSPACE --> SOUL["SOUL.md"]
    WORKSPACE --> USER["USER.md"]
    WORKSPACE --> MEMORY["MEMORY.md"]
    WORKSPACE --> AGENTS["AGENTS.md"]

    %% OpenClaw config
    OPENCLAW_DIR --> OC_CONFIG["openclaw.json"]
    OPENCLAW_DIR --> DEVICES["devices/"]

    DEVICES --> PAIRED["paired.json"]
    DEVICES --> PENDING["pending.json"]

    %% Local
    LOCAL --> STATE["state/syncthing/"]
    LOCAL --> VENV["venv-voice/"]

    style VAULT fill:#e6f3ff
    style SYSTEM fill:#fff4e6
    style OPENCLAW_DIR fill:#e6ffe6
```

---

## 8. Command & Service Reference Map

```mermaid
flowchart LR
    subgraph USER["User Types Command"]
        CMD["nazar-status<br/>nazar-logs<br/>nazar-restart<br/>nazar-audit"]
    end

    subgraph HELPERS["Helper Scripts<br/>/home/debian/bin/"]
        direction TB
        STATUS["nazar-status<br/>→ systemctl --user status"]
        LOGS["nazar-logs<br/>→ journalctl --user"]
        RESTART["nazar-restart<br/>→ systemctl --user restart"]
        AUDIT["nazar-audit<br/>→ Security checks"]
    end

    subgraph EXECUTION["systemd User Services"]
        SYSTEMD["systemd --user<br/>(as nazar)"]
        OC_SVC["openclaw.service"]
        ST_SVC["syncthing.service"]
    end

    subgraph RESULTS["Results"]
        OC_STATUS["OpenClaw Status"]
        ST_STATUS["Syncthing Status"]
        SVC_LOGS["Service Logs"]
        AUDIT_REPORT["Audit Report"]
    end

    USER --> HELPERS
    STATUS --> SYSTEMD
    LOGS --> SYSTEMD
    RESTART --> SYSTEMD

    SYSTEMD --> OC_SVC
    SYSTEMD --> ST_SVC

    OC_SVC --> OC_STATUS
    ST_SVC --> ST_STATUS
    SYSTEMD --> SVC_LOGS
    AUDIT --> AUDIT_REPORT

    style HELPERS fill:#fff4e6
    style EXECUTION fill:#e6f3ff
```

---

## 9. Complete Data Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Capture: User has idea

    Capture --> Voice: Voice message
    Capture --> Text: Type in Obsidian
    Capture --> CLI: Gateway API

    Voice --> Transcribe: Whisper STT
    Transcribe --> Process: OpenClaw
    Text --> Process: Direct save
    CLI --> Process: Gateway API

    Process --> AI_Analyze: LLM processing
    AI_Analyze --> Enrich: Add metadata

    Enrich --> Write_Vault: Save to daily note
    Write_Vault --> Syncthing_Detect: File change on disk

    Syncthing_Detect --> Sync_Devices: Syncthing P2P sync

    Sync_Devices --> Available: On all devices
    Available --> Laptop_Update: Laptop Obsidian refreshes
    Available --> Phone_Update: Phone Obsidian refreshes

    Laptop_Update --> Synced: In sync
    Phone_Update --> Synced: In sync

    Synced --> Query: User asks Nazar
    Query --> AI_Search: Search vault
    AI_Search --> Respond: Generate answer
    Respond --> [*]

    Synced --> Archive: Project complete
    Archive --> [*]
```

---

## Legend

| Symbol | Meaning |
|--------|---------|
| Solid arrow | Direct data flow |
| Dashed arrow | Trigger/indirect |
| Double arrow | Bidirectional Syncthing sync |
| systemd | User-scoped service (runs as nazar) |
| Tailscale | WireGuard VPN mesh (100.x.x.x) |

---

*Generated: 2026-02-11*
*For interactive viewing, use a Mermaid-compatible markdown viewer or paste into [Mermaid Live Editor](https://mermaid.live)*
