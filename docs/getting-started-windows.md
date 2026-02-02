# Getting Started with GitHub Copilot CLI on Windows

A beginner-friendly guide to setting up GitHub Copilot CLI (prerelease) on Windows, from scratch.

> **What is GitHub Copilot CLI?**  
> It's an AI-powered assistant that lives in your terminal. You can ask it questions, have it write code, run commands, analyze files, and much more—all through conversation. Think of it as having a knowledgeable developer sitting next to you, available 24/7.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1: Install Windows Terminal](#step-1-install-windows-terminal)
3. [Step 2: Install PowerShell 7](#step-2-install-powershell-7)
4. [Step 3: Set PowerShell 7 as Your Default](#step-3-set-powershell-7-as-your-default)
5. [Step 4: Install GitHub Copilot CLI](#step-4-install-github-copilot-cli)
6. [Step 5: Sign In](#step-5-sign-in)
7. [Step 6: Enable Experimental Features](#step-6-enable-experimental-features)
8. [Step 7: Set Your Preferred AI Model](#step-7-set-your-preferred-ai-model)
9. [Step 8: Set Up WorkIQ](#step-8-set-up-workiq)
10. [Using Skills](#using-skills)
11. [Next Steps](#next-steps)

---

## Prerequisites

Before we begin, make sure you have:

- **Windows 10 or 11** (Windows 11 recommended)
- **A GitHub account** with access to GitHub Copilot
- **An internet connection**

That's it! We'll install everything else together.

---

## Step 1: Install Windows Terminal

### What is Windows Terminal?

Windows Terminal is Microsoft's modern terminal application. It's faster, prettier, and more capable than the old Command Prompt or PowerShell windows. It supports tabs (like a web browser), better text rendering, and customization.

### Why do I need it?

While Copilot CLI can technically run in the old Command Prompt, Windows Terminal provides a much better experience—especially for the rich text output that Copilot produces.

### Installation

1. Press the **Windows key** on your keyboard
2. Type `Microsoft Store` and press Enter
3. In the Microsoft Store, search for `Windows Terminal`
4. Click **Get** or **Install**

Alternatively, if you already have `winget` (Windows Package Manager), open any terminal and run:

```powershell
winget install Microsoft.WindowsTerminal
```

### How do I know it worked?

Press the Windows key, type `Windows Terminal`, and you should see it appear. Open it—you'll see a modern-looking terminal window, probably with a PowerShell tab.

---

## Step 2: Install PowerShell 7

### What is PowerShell 7?

PowerShell is a command-line shell and scripting language from Microsoft. Windows comes with PowerShell 5.1 built-in, but **PowerShell 7** is the modern, cross-platform version with better features and performance.

### Why do I need it?

GitHub Copilot CLI works best with PowerShell 7+. The older PowerShell 5.1 that comes with Windows is missing features and has some compatibility quirks. PowerShell 7 is actively maintained and receives regular updates.

### Installation

Open Windows Terminal (from Step 1) and run:

```powershell
winget install Microsoft.PowerShell
```

You'll see output showing the download and installation progress. When it's done, you'll see a success message.

### How do I know it worked?

Close and reopen Windows Terminal. Then run:

```powershell
$PSVersionTable.PSVersion
```

You should see version **7.x.x** (like 7.4.0 or higher). If you see version 5.x, you're still using the old PowerShell—continue to the next step to fix that.

---

## Step 3: Set PowerShell 7 as Your Default

Now that PowerShell 7 is installed, let's make it the default shell in Windows Terminal.

### Why does this matter?

When you open Windows Terminal, it might still open the old PowerShell 5.1 by default. We want it to open PowerShell 7 instead, so you're always using the modern version.

### Configuration

1. Open **Windows Terminal**
2. Click the **down arrow (⌄)** next to the tabs at the top
3. Select **Settings** (or press `Ctrl + ,`)
4. In the left sidebar, find **Startup**
5. Look for **Default profile**
6. Change it from "Windows PowerShell" to **"PowerShell"** (the one without "Windows" in the name—that's PowerShell 7)
7. Click **Save** at the bottom right

### How do I know it worked?

Close Windows Terminal completely and reopen it. The tab should now say "PowerShell" (not "Windows PowerShell"). Run `$PSVersionTable.PSVersion` again to confirm you see version 7.x.

---

## Step 4: Install GitHub Copilot CLI

Now for the main event—installing GitHub Copilot CLI itself.

### What are we installing?

The GitHub Copilot CLI is a command-line tool called `copilot`. It connects to GitHub's AI service to provide intelligent assistance right in your terminal.

### Installation

In Windows Terminal (with PowerShell 7), run:

```powershell
winget install GitHub.Copilot.Prerelease
```

> **Note:** This is the prerelease version with the latest features. It may occasionally have bugs, but you get access to new capabilities before they're widely released. (There's also a stable version at `GitHub.Copilot` if you prefer stability over new features.)

### How do I know it worked?

Run:

```powershell
copilot --version
```

You should see a version number displayed. If you get an error like "command not found," close and reopen Windows Terminal (the PATH needs to refresh), then try again.

---

## Step 5: Sign In

Before you can use Copilot CLI, you need to authenticate with your GitHub account.

### Sign-In Process

1. Start a Copilot CLI session:

   ```powershell
   copilot
   ```

2. Once inside the session, type:

   ```
   /login
   ```

3. This will:
   - Open your web browser to a GitHub authentication page
   - Ask you to authorize the application
   - Return you to the terminal once complete

### How do I know it worked?

After completing the browser authentication, you'll see a confirmation message in the terminal. You can now start chatting with Copilot!

---

## Step 6: Enable Experimental Features

The prerelease version of Copilot CLI has experimental features that provide enhanced capabilities. Let's turn them on.

### What are experimental features?

These are new capabilities that are still being tested. They might change or be removed in future versions, but they often include the most powerful and useful features. Since you're using the prerelease anyway, you might as well get the full experience!

### Enable Them

You can enable experimental features by starting Copilot with the `--experimental` flag:

```powershell
copilot --experimental
```

Or, to make it permanent, you can set it in the config. Inside a Copilot session, use the `/config` command, or edit your configuration file at `~/.copilot/config.json`.

---

## Step 7: Set Your Preferred AI Model

Copilot CLI can use different AI models. For the best results, I recommend using **Claude Opus 4.5**.

### What's Claude Opus?

Claude is an AI model made by Anthropic. The "Opus" version is their most capable model—it's excellent at complex reasoning, coding, and nuanced tasks. While it may be slightly slower than smaller models, the quality difference is noticeable.

> **Microsoft FTEs:** You get **unlimited usage** of all models, including Claude Opus 4.5. Take advantage of this—use the best model available!

### Available Models

As of this writing, the available models include:
- `claude-opus-4.5` - Most capable (recommended)
- `claude-sonnet-4.5` - Good balance of speed and capability
- `claude-sonnet-4` - Fast and capable
- `gpt-5.2-codex` - OpenAI's coding model
- `gpt-5.1`, `gpt-5` - OpenAI models
- And more (run `copilot --help` to see all options)

### Set the Model

You can specify the model when starting Copilot:

```powershell
copilot --model claude-opus-4.5
```

To make this your default, you can create an alias in your PowerShell profile or set it in your configuration.

---

## Step 8: Set Up WorkIQ

WorkIQ is a Microsoft plugin that connects Copilot CLI to your Microsoft 365 data—emails, meetings, files, and more. This is **required** for features like generating presentations and weekly summaries.

### What can WorkIQ do?

- Summarize your recent emails
- Find information from past meetings
- Search your OneDrive files
- Help you prepare for upcoming meetings
- Generate weekly work summaries
- **Create PowerPoint presentations from your work data**

### Installation

The easiest way to install WorkIQ is through Copilot CLI itself. Start a Copilot session:

```powershell
copilot
```

Then add the plugins marketplace (one-time setup):

```
/plugin marketplace add github/copilot-plugins
```

Then install WorkIQ:

```
/plugin install workiq@copilot-plugins
```

Restart Copilot CLI after installation.

### First-Time Use

Try asking Copilot something that requires WorkIQ. Inside a Copilot session:

```
What meetings do I have this week?
```

If prompted, accept the End User License Agreement (EULA) by following the on-screen instructions.

### Official Documentation

For more details, troubleshooting, and advanced configuration, see the official WorkIQ documentation:

🔗 **[WorkIQ MCP on GitHub](https://github.com/microsoft/work-iq-mcp)**

---

## Using Skills

Skills are like "expertise packs" for Copilot CLI. They give it specialized knowledge about specific topics or tasks.

### What are Skills?

Think of skills as instruction manuals that Copilot reads before helping you with certain tasks. A skill might teach Copilot:
- How your team writes commit messages
- Best practices for a specific framework
- Your company's coding standards
- How to generate specific types of reports

### Installing Skills from This Repository

This repository contains useful skills including the **weekly-impact-summary** skill that generates PowerPoint presentations of your weekly achievements. To install them:

1. **Clone this repository** (if you haven't already):

   ```powershell
   cd ~\repos
   git clone git@github.com:ericchansen/skills.git
   cd skills
   ```

   Or using HTTPS:

   ```powershell
   cd ~\repos
   git clone https://github.com/ericchansen/skills.git
   cd skills
   ```

2. **Run the setup script**:

   ```powershell
   .\setup.ps1
   ```

3. The script will:
   - Clone additional skill repositories from Anthropic and GitHub
   - Ask you where to store them (default: `~/repos`)
   - Handle any naming conflicts between skill sources
   - Create junctions/symlinks to `~/.copilot/skills`

> **Note:** If the clone fails, it's usually because you don't have SSH keys set up with GitHub. The script will show you the HTTPS URLs to clone manually if this happens.

### Skills in This Repository

| Skill | Description |
|-------|-------------|
| **git-commit-message** | Helps you write professional Git commit messages following best practices |
| **weekly-impact-summary** | Generates evidence-based weekly impact summaries and **PowerPoint presentations** using WorkIQ to pull your actual work data |

### The Weekly Impact Summary Skill

This is particularly useful for anyone who needs to report on their work. Instead of trying to remember what you did last week, you can simply ask inside a Copilot session:

```
Generate my weekly impact summary
```

Or for a presentation:

```
Create a PowerPoint summarizing my work this week
```

With WorkIQ connected, it will pull your actual emails, meetings, and files to create an accurate summary focused on measurable business outcomes.

### Creating Your Own Skills

The easiest way to add a skill is simply to **ask Copilot to create one for you**. Inside a Copilot session, just say:

```
Create a skill that helps me write Python code following PEP 8 style guidelines
```

Copilot will create the skill files and set everything up. Skills are stored in `~/.copilot/skills/` by default.

---

## Next Steps

Congratulations! You now have a fully configured GitHub Copilot CLI. 

### Try the Weekly Summary Skill

Once you've installed the skills from this repository and have WorkIQ set up, start a Copilot session and try:

```powershell
copilot --model claude-opus-4.5 --experimental
```

Then inside the session:

```
Generate my weekly impact summary
```

Or for a PowerPoint presentation:

```
Create a PowerPoint summarizing my work this week
```

### Learn More

- **[GitHub Copilot Documentation](https://docs.github.com/en/copilot)** - Official docs
- **[Agent Skills Standard](https://github.com/agentskills/agentskills)** - Learn more about creating skills
- **[WorkIQ Documentation](https://github.com/microsoft/work-iq-mcp)** - Troubleshooting and advanced configuration
- **[This Repository's README](../README.md)** - More details on the skills in this repo

---

*Now go generate that PowerPoint! 🚀*
