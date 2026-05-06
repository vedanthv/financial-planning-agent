# OpenAI Agents SDK MCP Architecture

This architecture allows an AI agent to control a real browser through an MCP server using Playwright.

The Python application launches a Playwright MCP process using `npx`, and the MCP server manages a Chromium browser instance.

The browser can then:

* open websites
* click buttons
* fill forms
* scrape content
* automate workflows

---

# High-Level Architecture

```mermaid
flowchart LR
    A[AI Agent] --> B[Python Application]
    B --> C[MCPServerStdio]
    C --> D[Playwright MCP Server]
    D --> E[Chromium Browser]
    E --> F[Websites]
```

---

# Component Responsibilities

| Component          | Responsibility                               |
| ------------------ | -------------------------------------------- |
| AI Agent           | Decides browsing actions                     |
| Python Application | Creates and manages MCP server               |
| MCPServerStdio     | Handles process communication                |
| Playwright MCP     | Converts agent requests into browser actions |
| Chromium Browser   | Executes real browser interactions           |
| Websites           | External systems being accessed              |

---

# Process Communication Design

`MCPServerStdio` communicates with the Playwright MCP process using stdin/stdout pipes.

This creates a lightweight local IPC (inter-process communication) architecture.

```mermaid
flowchart LR
    A[Python Process]
    A --> B[stdin/stdout Pipes]
    B --> C[Playwright MCP Process]
```

---

# Browser Automation Flow

The AI agent does not directly control the browser.

Instead:

1. Agent sends instructions
2. MCP server interprets them
3. Playwright executes browser automation
4. Browser interacts with website
5. Results return back to agent

```mermaid
sequenceDiagram
    participant Agent
    participant MCP
    participant Browser
    participant Website

    Agent->>MCP: Open website
    MCP->>Browser: Launch Chromium
    Browser->>Website: HTTP request
    Website-->>Browser: HTML response
    Browser-->>MCP: Page content
    MCP-->>Agent: Structured result
```

---

# Runtime Architecture in Docker

Inside Docker/AWS environments, the system dynamically discovers the installed Chromium executable path.

This avoids hardcoding browser versions.

```mermaid
flowchart TD
    A[Container Startup]
    --> B[Detect Docker or AWS]
    --> C[Search Chromium Path]
    --> D[Configure Executable Path]
    --> E[Launch Playwright MCP]
```

---

# Why Headless Mode Is Used

The browser runs in headless mode because this system is designed for:

* servers
* containers
* CI/CD pipelines
* cloud environments

No graphical desktop is required.

```mermaid
flowchart LR
    A[Playwright MCP]
    --> B[Headless Chromium]
    --> C[Website Automation]
```

---

# Security Isolation Design

The browser runs in isolated mode to prevent session sharing.

Each MCP session gets a clean browser environment.

Benefits:

* no cookie leakage
* no shared sessions
* safer multi-user execution
* reproducible automation

```mermaid
flowchart TD
    A[New MCP Session]
    --> B[Fresh Browser Context]
    --> C[Independent Cookies]
    --> D[Independent Storage]
```

---

# End-to-End Request Lifecycle

```mermaid
flowchart TD
    A[User Request]
    --> B[AI Agent Decision]
    --> C[MCP Browser Command]
    --> D[Playwright Automation]
    --> E[Chromium Browser]
    --> F[Target Website]
    --> G[Extracted Data]
    --> H[AI Agent Response]
```
