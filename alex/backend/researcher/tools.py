"""
Tools for the Alex Researcher agent
"""

# Module documentation
#
# This file contains tool functions used by the AI agent.
#
# These tools allow the agent to:
# - communicate with backend APIs
# - ingest financial research
# - store analysis in vector databases
# - interact with external systems

# ==========================================================
# IMPORTS
# ==========================================================

import os

# os:
# Operating system utilities
#
# Used here for:
# - reading environment variables

from typing import Dict, Any

# Type hints for better readability and validation
#
# Dict[str, Any]
# means:
# dictionary with string keys and any value types

from datetime import datetime, UTC

# datetime:
# used for timestamps
#
# UTC:
# timezone-aware UTC timestamps

import httpx

# httpx:
# modern Python HTTP client
#
# Similar to requests library
#
# Used for:
# - sending API requests
# - handling HTTP responses

from agents import function_tool

# function_tool decorator
#
# Registers a Python function as a callable AI agent tool
#
# After decoration:
# the AI agent can dynamically invoke this function

from tenacity import retry, stop_after_attempt, wait_exponential

# tenacity:
# retry framework/library
#
# Used for:
# - automatic retries
# - exponential backoff
# - handling temporary failures

# ==========================================================
# ENVIRONMENT CONFIGURATION
# ==========================================================

# Read backend API endpoint from environment variable
#
# Example:
# https://abc123.execute-api.us-east-1.amazonaws.com/prod/ingest
#
# Environment variables avoid hardcoding configuration
ALEX_API_ENDPOINT = os.getenv("ALEX_API_ENDPOINT")

# Read API key from environment variable
#
# Used for authenticating requests to API Gateway
#
# Client sends:
# x-api-key: <value>
ALEX_API_KEY = os.getenv("ALEX_API_KEY")


# ==========================================================
# INTERNAL INGEST FUNCTION
# ==========================================================

def _ingest(document: Dict[str, Any]) -> Dict[str, Any]:

    """
    Internal function to make the actual API call.
    """

    # This function:
    # - sends HTTP request
    # - communicates with backend ingestion API
    # - returns JSON response

    # Create synchronous HTTP client
    #
    # "with" automatically:
    # - opens client
    # - manages connections
    # - closes resources cleanly
    with httpx.Client() as client:

        # Send HTTP POST request
        #
        # Flow:
        #
        # Python Tool
        #      ↓
        # API Gateway
        #      ↓
        # Lambda
        #      ↓
        # Vector Database
        response = client.post(

            # Backend API endpoint
            #
            # Example:
            # https://api.example.com/prod/ingest
            ALEX_API_ENDPOINT,

            # JSON request body
            #
            # Automatically serialized to JSON
            #
            # Example:
            # {
            #   "text": "...",
            #   "metadata": {...}
            # }
            json=document,

            # HTTP headers
            headers={

                # API Gateway API key authentication
                #
                # Client must send:
                # x-api-key header
                "x-api-key": ALEX_API_KEY
            },

            # Request timeout in seconds
            #
            # Prevents hanging forever
            #
            # Important because:
            # - SageMaker inference may be slow
            # - network latency may occur
            timeout=30.0
        )

        # Raise exception for HTTP errors
        #
        # Examples:
        # 400 Bad Request
        # 401 Unauthorized
        # 403 Forbidden
        # 500 Internal Server Error
        #
        # Without this:
        # failed responses may silently continue
        response.raise_for_status()

        # Parse JSON response into Python dictionary
        #
        # Example response:
        # {
        #   "document_id": "abc123"
        # }
        return response.json()


# ==========================================================
# RETRY WRAPPER
# ==========================================================

# Retry decorator
#
# Automatically retries failed requests
#
# Important for:
# - SageMaker cold starts
# - transient network failures
# - temporary infrastructure delays
@retry(

    # Maximum retry attempts
    #
    # Total:
    # initial request + retries
    stop=stop_after_attempt(3),

    # Exponential backoff strategy
    #
    # Example:
    # attempt 1 -> wait 1 sec
    # attempt 2 -> wait 2 sec
    # attempt 3 -> wait 4 sec
    #
    # min/max prevent extreme delays
    wait=wait_exponential(
        multiplier=1,
        min=1,
        max=10
    )
)

def ingest_with_retries(document: Dict[str, Any]) -> Dict[str, Any]:

    """
    Ingest with retry logic for SageMaker cold starts.
    """

    # Wrapper around _ingest()
    #
    # If _ingest throws exception:
    # tenacity retries automatically
    return _ingest(document)


# ==========================================================
# AGENT TOOL FUNCTION
# ==========================================================

# Register function as AI agent tool
#
# Agent can now dynamically call:
# ingest_financial_document(...)
#
# during reasoning/workflows
@function_tool

def ingest_financial_document(
    topic: str,
    analysis: str
) -> Dict[str, Any]:

    """
    Ingest a financial document into the Alex knowledge base.

    Args:
        topic:
            Subject/title of analysis

            Examples:
            - AAPL Stock Analysis
            - Retirement Planning Guide

        analysis:
            Full financial analysis text

    Returns:
        Dictionary containing:
        - success status
        - document ID
        - error message if failure
    """

    # ======================================================
    # CONFIG VALIDATION
    # ======================================================

    # Ensure API configuration exists
    #
    # Useful for:
    # - local development
    # - testing environments
    # - offline execution
    #
    # Prevents crashes if env vars missing
    if not ALEX_API_ENDPOINT or not ALEX_API_KEY:

        return {

            # Failure status
            "success": False,

            # Informative error
            "error": (
                "Alex API not configured. "
                "Running in local mode."
            )
        }
    
    # ======================================================
    # BUILD DOCUMENT PAYLOAD
    # ======================================================

    # Create ingestion payload
    #
    # Structure:
    #
    # {
    #   "text": "...",
    #   "metadata": {
    #       "topic": "...",
    #       "timestamp": "..."
    #   }
    # }
    document = {

        # Main financial analysis text
        "text": analysis,

        # Metadata object
        #
        # Useful for:
        # - search filtering
        # - auditing
        # - retrieval context
        "metadata": {

            # Analysis topic/title
            "topic": topic,

            # UTC ISO8601 timestamp
            #
            # Example:
            # 2026-05-06T08:30:00+00:00
            #
            # timezone-aware timestamp
            "timestamp": datetime.now(UTC).isoformat()
        }
    }
    
    # ======================================================
    # INGEST DOCUMENT
    # ======================================================

    try:

        # Send document to backend API
        #
        # Includes automatic retries
        result = ingest_with_retries(document)

        # Return structured success response
        return {

            # Success indicator
            "success": True,

            # Extract backend-generated document ID
            #
            # Example:
            # "doc_abc123"
            #
            # .get() safely avoids KeyError
            "document_id": result.get("document_id"),

            # Human-readable success message
            "message": (
                f"Successfully ingested analysis for {topic}"
            )
        }

    # Catch ALL exceptions
    #
    # Examples:
    # - timeout errors
    # - HTTP failures
    # - connection errors
    # - JSON parsing errors
    except Exception as e:

        # Return structured failure response
        #
        # Prevents tool crash
        return {

            # Failure indicator
            "success": False,

            # Convert exception to readable string
            "error": str(e)
        }