# Custom Agent Skills

Personal collection of [Agent Skills](https://agentskills.io) for GitHub Copilot CLI and other AI agents.

> **New to GitHub Copilot CLI?** Check out the [Getting Started Guide](docs/getting-started-windows.md) for a beginner-friendly walkthrough of installation and setup on Windows.

## Skills

- **git-commit-message** - Expert guidance for writing professional Git commit messages following industry best practices from [Chris Beams' guide](https://cbea.ms/git-commit/)
- **weekly-impact-summary** - Generate evidence-based weekly impact summaries focused on measurable business outcomes using WorkIQ integration

## Installation

To use these skills with GitHub Copilot CLI:

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/skills.git ~/repos/skills
   cd ~/repos/skills
   ```

2. Run the setup script:
   
   **Windows (PowerShell):**
   ```powershell
   ./setup.ps1
   ```

   **macOS/Linux:**
   ```bash
   ./setup.sh
   ```

The setup script will:
- Clone skills from [Anthropic](https://github.com/anthropics/skills) and [GitHub](https://github.com/github/awesome-copilot)
- Detect any naming conflicts between sources
- Let you choose which source to use for conflicting skills
- Create symlinks/junctions to `~/.copilot/skills`

Run the setup script again at any time to update skills from external repositories.

## About Agent Skills

Agent Skills are an [open standard](https://github.com/agentskills/agentskills) maintained by Anthropic for giving agents new capabilities and expertise. Skills are folders containing:

- `SKILL.md` (required) - Instructions with YAML frontmatter (name, description) and markdown body
- Optional bundled resources: scripts, references, and assets

## License

MIT
