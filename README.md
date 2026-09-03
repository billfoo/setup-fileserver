# Secure PHP/Apache Docker Server Setup

An automated, highly secure bash script to deploy a standalone PHP 8.2 Apache web server using Docker. 

This script was designed with maximum security in mind. It is perfect for hosting private APIs, DNS workers, or backend scripts that require strict IP whitelisting and an isolated environment.

## ✨ Features

*   **🚀 Automated Deployment:** Instantly spins up a `php:8.2-apache` Docker container.
*   **🛡️ Integrated UFW Firewall:** Interactive prompt to either open the port to the public or strictly restrict access to a single IP address (e.g., your Main Server/API).
*   **👻 Ghost Container Cleanup:** Automatically detects and destroys conflicting or hidden containers that block the required port.
*   **💾 Persistent & Safe Storage:** Your PHP scripts are stored on the host machine and mounted into the container as **Read-Only (`ro`)**. This prevents malicious scripts from modifying your files.
*   **🧠 Intelligent Configuration Memory:** Remembers your firewall settings for future updates.
*   **🧹 Clean Uninstallation:** Built-in option to completely remove the container, firewall rules, configurations, and data without leaving traces.

## 📋 Prerequisites

Before running the script, ensure your server meets the following requirements:
*   A Linux-based OS (Ubuntu/Debian recommended).
*   **Docker** installed and running.
*   **UFW** (Uncomplicated Firewall) installed and enabled.
*   **Root privileges** (run the script as root or via `sudo`).

## 🚀 Installation & Usage

You can download and run the script directly with a single command:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/billfoo/setup-fileserver/main/fileserver.sh)
```

### Setup Process
1. **Run the command above.**
2. **Choose your Firewall Mode:** 
   * *Option 1 (Open):* Opens the port for the entire internet (not recommended for private APIs).
   * *Option 2 (Restricted):* Prompts you to enter a specific IP address. Only this IP will be able to access the server.
3. **Upload your files:**
   Place your PHP scripts (e.g., `dns_worker.php`) or HTML files into the newly created directory on your host:
   `/opt/public-files`
4. **Set Permissions:**
   Ensure the web server can read your files:
   `chmod 644 /opt/public-files/*`
5. **Access the server:**
   Your server is now available on port `8080` (e.g., `http://YOUR_SERVER_IP:8080/dns_worker.php`).

## ⚙️ Configuration & Paths

*   **Web Directory (Host):** `/opt/public-files` *(Place your files here)*
*   **Web Directory (Container):** `/var/www/html`
*   **Port:** `8080`
*   **Config File:** `/opt/secure-server-firewall.conf` *(Stores your IP-whitelist settings)*
*   **Container Name:** `secure-php-server`

## 🔄 Reconfiguration

If you want to change the allowed IP address or reset the server while **keeping your files intact**, simply run the installation command again. 

The script will detect the existing container and present an interactive menu:
Select **Option 2 (Reinstall/Reconfigure)**. The script will automatically clean up the old UFW rules, ask for your new IP, and restart the container without touching your PHP files.

## 🗑️ Uninstallation

To completely remove the server and all its traces from your system, run the installation command again:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/billfoo/setup-fileserver/main/fileserver.sh)
```

When prompted, select **Option 3 (Completely remove)**. The script will perform a clean wipe:
1. Stops and removes the Docker container.
2. Finds and removes any ghost containers on the port.
3. Safely deletes the UFW firewall rules created by this script.
4. Deletes the configuration file.
5. Asks if you want to permanently delete your hosted files in `/opt/public-files`.

## 🔒 Security Notice

This script configures `ufw` (Uncomplicated Firewall). Ensure your external Cloud Firewall (e.g., AWS Security Groups, Hetzner Cloud Firewall) also permits traffic on Port `8080` from your allowed IP, and that Port `22` remains open so you don't lock yourself out of SSH.
