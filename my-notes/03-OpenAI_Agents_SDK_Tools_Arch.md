# OpenAI Agents SDK - Tool Calling Architecture

This module exposes an AI agent tool that ingests financial analysis documents into the Alex knowledge base through an external API.

The tool performs:

* document creation
* API communication
* retry handling
* metadata enrichment
* error handling

---

# High-Level Architecture

```mermaid
flowchart LR
    A[AI Agent]
    --> B[Function Tool]

    B --> C[HTTP Client]

    C --> D[API Gateway]

    D --> E[Lambda Function]

    E --> F[SageMaker Embeddings]

    E --> G[Vector Storage]
```

---

# Main Components

| Component        | Responsibility                 |
| ---------------- | ------------------------------ |
| AI Agent         | Generates financial analysis   |
| `@function_tool` | Exposes callable tool to agent |
| `httpx.Client`   | Sends HTTP requests            |
| API Gateway      | Public ingestion endpoint      |
| Lambda           | Backend processing             |
| SageMaker        | Generates embeddings           |
| Vector Storage   | Stores searchable vectors      |

---

# Tool Registration Design

The decorator:

```python id="jlwmqq"
@function_tool
```

registers the Python function as a callable AI agent tool.

This allows the agent to dynamically invoke it during reasoning.

---

# Tool Invocation Flow

```mermaid
sequenceDiagram
    participant Agent
    participant Tool
    participant API
    participant Lambda
    participant VectorDB

    Agent->>Tool: ingest_financial_document()
    Tool->>API: HTTP POST
    API->>Lambda: Invoke backend
    Lambda->>VectorDB: Store embeddings
    Lambda-->>API: Success response
    API-->>Tool: JSON response
    Tool-->>Agent: document_id
```

---

# API Communication Architecture

The system uses synchronous HTTP communication through `httpx`.

```mermaid
flowchart LR
    A[Function Tool]
    --> B[httpx Client]

    B --> C[HTTPS Request]

    C --> D[Alex API Endpoint]
```

---

# Authentication Design

Authentication is handled using API keys stored in environment variables.

```mermaid
flowchart TD
    A[Environment Variables]
    --> B[ALEX_API_KEY]

    B --> C[HTTP Header]

    C --> D[x-api-key]
```

This avoids hardcoding secrets inside source code.

---

# Environment Configuration Design

The module reads configuration dynamically from environment variables.

```mermaid
flowchart TD
    A[Runtime Environment]
    --> B[ALEX_API_ENDPOINT]

    A --> C[ALEX_API_KEY]

    B --> D[HTTP Request Configuration]
    C --> D
```

Benefits:

* portable deployments
* secret isolation
* environment-specific configuration
* container compatibility

---

# Retry Architecture

The system includes retry handling using exponential backoff.

Purpose:

* handle SageMaker cold starts
* transient network failures
* temporary infrastructure latency

---

# Retry Flow

```mermaid
flowchart TD
    A[API Request]
    --> B{Success?}

    B -- Yes --> C[Return Result]

    B -- No --> D[Retry Logic]

    D --> E[Wait Exponentially]

    E --> A
```

---

# Exponential Backoff Strategy

Configuration:

```python id="jlwm11"
stop_after_attempt(3)
wait_exponential(min=1, max=10)
```

Retry timing example:

| Attempt | Wait Time |
| ------- | --------- |
| 1       | 1 second  |
| 2       | 2 seconds |
| 3       | 4 seconds |

This prevents overwhelming backend systems during failures.

---

# Backend Processing Pipeline

The backend ingestion API likely performs:

1. receive financial analysis
2. generate embeddings
3. store vectors
4. return document ID

---

# Backend System Design

```mermaid
flowchart TD
    A[Financial Analysis]
    --> B[API Gateway]

    B --> C[Lambda Function]

    C --> D[Generate Embeddings]

    D --> E[Store Vector Data]

    E --> F[Return Document ID]
```

---

# Metadata Enrichment Design

Before ingestion, metadata is added:

* topic
* UTC timestamp

This improves:

* searchability
* filtering
* auditing
* retrieval context

---

# Document Structure

```mermaid
flowchart TD
    A[Document Payload]
    --> B[text]

    A --> C[metadata]

    C --> D[topic]

    C --> E[timestamp]
```

---

# Error Handling Design

The system gracefully handles:

* missing configuration
* HTTP failures
* backend exceptions
* timeout issues

Instead of crashing, structured error responses are returned.

---

# Error Flow

```mermaid
flowchart TD
    A[Tool Execution]
    --> B{API Config Exists?}

    B -- No --> C[Return Local Mode Error]

    B -- Yes --> D[Send API Request]

    D --> E{Request Success?}

    E -- Yes --> F[Return Success]

    E -- No --> G[Return Structured Error]
```

---

# End-to-End Lifecycle

```mermaid
sequenceDiagram
    participant User
    participant Agent
    participant Tool
    participant API
    participant Backend

    User->>Agent: Financial analysis request
    Agent->>Tool: ingest_financial_document()
    Tool->>API: POST analysis
    API->>Backend: Process document
    Backend-->>API: document_id
    API-->>Tool: JSON response
    Tool-->>Agent: Success result
```
