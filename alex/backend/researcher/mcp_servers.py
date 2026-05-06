"""
MCP server configurations for the Alex Researcher
"""

# Module documentation
#
# This file contains helper functions for configuring
# MCP (Model Context Protocol) servers used by the AI system.
#
# In this case:
# - Playwright MCP server
# - Browser automation support
# - Web research capabilities

# Import MCP stdio server implementation
#
# MCPServerStdio launches MCP tools as subprocesses
# and communicates using:
#
# - stdin
# - stdout
#
# Architecture:
#
# Python App
#      ↓
# MCPServerStdio
#      ↓
# Playwright MCP Process
#      ↓
# Chromium Browser
from agents.mcp import MCPServerStdio


def create_playwright_mcp_server(timeout_seconds=60):

    """
    Create a Playwright MCP server instance for web browsing.

    Args:
        timeout_seconds:
            Maximum MCP client session timeout.

            If no activity occurs for this duration,
            the session can be terminated automatically.

            Default = 60 seconds

    Returns:
        MCPServerStdio instance configured for Playwright
    """

    # ==========================================================
    # PLAYWRIGHT MCP COMMAND ARGUMENTS
    # ==========================================================
    #
    # These arguments will eventually become:
    #
    # npx @playwright/mcp@latest --headless ...
    #
    # The MCP server internally launches Chromium
    # and exposes browser automation tools to the AI agent.

    args = [

        # npm package to execute
        #
        # @playwright/mcp
        # = official Playwright MCP server
        #
        # @latest ensures latest package version is used
        "@playwright/mcp@latest",

        # Run browser in headless mode
        #
        # No visible GUI window
        #
        # Required for:
        # - servers
        # - Docker containers
        # - cloud execution
        "--headless",

        # Create isolated browser session
        #
        # Prevents:
        # - cookie sharing
        # - session leakage
        # - shared browser state
        #
        # Each AI session gets clean browser context
        "--isolated",

        # Disable Chromium sandbox
        #
        # Often required in:
        # - Docker
        # - restricted Linux environments
        # - AWS Lambda/container runtimes
        #
        # Without this, Chromium may fail to launch
        "--no-sandbox",

        # Ignore SSL/HTTPS certificate errors
        #
        # Useful for:
        # - development environments
        # - self-signed certificates
        # - internal corporate websites
        "--ignore-https-errors",

        # Override browser user-agent string
        #
        # Makes automation browser appear like:
        # Chrome on Windows desktop
        #
        # Helps reduce bot detection
        "--user-agent",

        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/125.0 Safari/537.36"
    ]
    
    # ==========================================================
    # ENVIRONMENT DETECTION
    # ==========================================================
    #
    # In Docker/AWS environments:
    # Playwright sometimes cannot automatically locate Chrome.
    #
    # This block dynamically finds Chromium executable path
    # and explicitly passes it to Playwright.

    import os

    # os:
    # operating system utilities
    #
    # Used for:
    # - checking files
    # - reading environment variables

    import glob

    # glob:
    # filesystem pattern matching utility
    #
    # Used to dynamically search for Chrome executable

    # Detect Docker container or AWS runtime
    #
    # /.dockerenv exists in many Docker containers
    #
    # AWS_EXECUTION_ENV commonly exists in AWS runtimes
    #
    # Examples:
    # - ECS
    # - Lambda containers
    # - SageMaker
    if os.path.exists("/.dockerenv") or os.environ.get("AWS_EXECUTION_ENV"):

        # ======================================================
        # DYNAMIC CHROME DISCOVERY
        # ======================================================
        #
        # Playwright installs Chromium under:
        #
        # /root/.cache/ms-playwright/
        #
        # Version numbers vary:
        #
        # chromium-1208
        # chromium-1210
        # etc
        #
        # glob allows dynamic matching instead of hardcoding

        chrome_paths = glob.glob(

            # Pattern search
            #
            # Example match:
            #
            # /root/.cache/ms-playwright/
            # chromium-1208/chrome-linux64/chrome
            "/root/.cache/ms-playwright/chromium-*/chrome-linux*/chrome"
        )

        # If at least one Chrome executable found
        if chrome_paths:

            # Use first discovered Chrome executable
            #
            # Usually only one exists
            chrome_path = chrome_paths[0]

            # Debug logging
            #
            # Helpful for:
            # - container debugging
            # - deployment troubleshooting
            print(f"DEBUG: Found Chrome at: {chrome_path}")

            # Add executable path argument
            #
            # Final command becomes:
            #
            # npx @playwright/mcp@latest \
            #   --executable-path /path/to/chrome
            #
            # This tells Playwright EXACTLY where Chrome exists
            args.extend([
                "--executable-path",
                chrome_path
            ])

        else:

            # ==================================================
            # FALLBACK CHROME PATH
            # ==================================================
            #
            # Used if dynamic search fails.
            #
            # Provides hardcoded backup path.

            print(
                "DEBUG: Chrome not found via glob, "
                "using fallback path"
            )

            args.extend([

                "--executable-path",

                # Hardcoded fallback Chromium path
                "/root/.cache/ms-playwright/"
                "chromium-1208/chrome-linux64/chrome"
            ])
    
    # ==========================================================
    # MCP PROCESS CONFIGURATION
    # ==========================================================
    #
    # Defines subprocess execution parameters.
    #
    # Equivalent shell command:
    #
    # npx @playwright/mcp@latest --headless ...

    params = {

        # Executable command
        #
        # npx runs Node.js packages dynamically
        "command": "npx",

        # CLI arguments passed to npx
        "args": args
    }
    
    # ==========================================================
    # CREATE MCP SERVER INSTANCE
    # ==========================================================
    #
    # Creates stdio-based MCP server connection.
    #
    # Architecture:
    #
    # Python Application
    #      ↓
    # MCPServerStdio
    #      ↓
    # Playwright MCP Process
    #      ↓
    # Chromium Browser
    #
    # The returned object can now:
    # - launch browser
    # - open websites
    # - click buttons
    # - scrape pages
    # - extract content
    # - automate workflows

    return MCPServerStdio(

        # Process execution configuration
        params=params,

        # Maximum MCP client session timeout
        client_session_timeout_seconds=timeout_seconds
    )