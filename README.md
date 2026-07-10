# Claude Jumpserver Proxy Setup

A secure, offline-compatible proxy wrapper system that allows running [Claude Code](https://github.com/anthropics/claude-code) on a headless jumpserver while executing commands remotely on a private GPU server and tunneling internet access via a local Mac connection.

## Architecture

This diagram visualizes how HTTP/HTTPS requests and shell commands are routed between your local machine, the jumpserver, and the private GPU server:

```mermaid
graph TD
    subgraph Local Machine (Macbook)
        LocalProxy[proxy.py - port 18888]
        Internet((Internet))
        LocalProxy --> Internet
    end

    subgraph Jumpserver
        Claude[Claude Code / pranay-claude]
        SSHTunnel[SSH Remote Forward - port 18888]
        Claude -->|HTTP/HTTPS API Calls| SSHTunnel
        SSHTunnel -->|Forwarded via SSH -R| LocalProxy
    end

    subgraph Private GPU Server (pranaysir)
        RemoteShell[bash - commands executed]
        RemoteForward[SSH Reverse Forward - port 18888]
        Claude -->|Intercepted Bash Commands| RemoteShell
        RemoteShell -->|Command network requests| RemoteForward
        RemoteForward -->|Forwarded via SSH -R| SSHTunnel
    end
```

## Features

1.  **Isolated Claude Accounts:** Support for multiple separate accounts (`pranay-claude` and `pranay-claude2`) running on the same jumpserver with isolated tokens/history/settings.
2.  **SSH Shell Proxying:** All shell operations are run remotely on `pranaysir` (the private GPU server) instead of local execution on the jumpserver, while sharing the same file paths.
3.  **Flexible Proxy Forwarding:** Easily toggle between direct internet access (when jumpserver network is working) and local proxy tunnel forwarding (when offline/behind a firewall).
4.  **Automatic SSHFS Mount Recovery:** Automatically mounts `pranaysir` drives on boot using a systemd user unit.
5.  **DNS Fallback Resolution:** Built-in DNS resolver inside `proxy.py` that queries public DNS (`8.8.8.8`) directly if Tailscale or local network DNS fails.

---

## Installation & Setup

### Step 1: Local Machine Configuration (Macbook)

1.  Keep the `proxy.py` file on your local machine.
2.  Run the proxy locally on port `18888`:
    ```bash
    python3 proxy.py 18888
    ```
3.  Log in to the jumpserver using SSH remote port forwarding:
    ```bash
    ssh -R 18888:127.0.0.1:18888 jumpserver
    ```

### Step 2: Jumpserver Configuration

1.  Clone this repository or copy its contents onto the jumpserver.
2.  Run the automated installer script:
    ```bash
    chmod +x install.sh
    ./install.sh
    ```

---

## Usage Guide

### 1. Toggling Proxy Mode
Use these simple commands on the jumpserver to enable or disable internet tunneling:

*   **To use jumpserver's direct internet connection (Default):**
    ```bash
    proxy-off
    ```
*   **To tunnel internet from your local machine (when jumpserver network is blocked):**
    ```bash
    proxy-on
    ```

### 2. Running Claude Code
*   **Account 1 (Primary):**
    ```bash
    pranay-claude
    ```
*   **Account 2 (Secondary):**
    ```bash
    pranay-claude2
    ```

### 3. Log in / Authenticating a Second Account
To log in with your second account (when using `pranay-claude2`), run:
```bash
pranay-claude2 auth
```

---

## Component Details

*   **`proxy.py`**: Local HTTP/HTTPS proxy with fallback DNS client.
*   **`pranay-claude` & `pranay-claude2`**: Unshare-namespace wrapper scripts that redirect user accounts and proxy states.
*   **`gpu-shell-pranay`**: Remote shell executor that routes commands via SSH to `pranaysir`.
*   **`mount-pranay`**: Idempotent shell script to safely mount sshfs directories.
*   **`mount-pranay.service`**: Systemd user service configuration to manage boot mounts.
