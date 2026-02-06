const pptxgen = require("pptxgenjs");

const pres = new pptxgen();
pres.author = "Eric Hansen";
pres.title = "Weekly Summary";
pres.subject = "Jan 24-30, 2026";
pres.layout = "LAYOUT_16x9";

// Single slide
let slide = pres.addSlide();

// Gradient header bar
slide.addShape("rect", {
  x: 0, y: 0, w: "100%", h: 1.1,
  fill: { type: "solid", color: "0F1419" }
});

// Accent gradient strip
slide.addShape("rect", {
  x: 0, y: 1.1, w: "100%", h: 0.08,
  fill: {
    type: "solid",
    color: "0078D4"
  }
});

// Title with gradient effect (using multiple text runs)
slide.addText([
  { text: "Weekly Summary", options: { color: "00B4D8", bold: true } },
  { text: "  •  Eric Hansen  •  Jan 24-30, 2026", options: { color: "888888", bold: false } }
], {
  x: 0.4, y: 0.35, w: 9.5, h: 0.5,
  fontSize: 24, fontFace: "Segoe UI Light"
});

// Layout: 3 columns - Internal | Accounts Left | Accounts Right
const col1X = 0.4;   // Internal
const col2X = 3.6;   // Citrix, TIBCO
const col3X = 6.8;   // NCR, IBM
const startY = 1.4;

// INTERNAL (left column - equal prominence)
slide.addText("INTERNAL", { x: col1X, y: startY, w: 2.5, h: 0.3, fontSize: 11, fontFace: "Segoe UI", color: "0078D4", bold: true });
slide.addText("Skills Matrix\n• Built demo web app (React/Node/PostgreSQL)\n• Finalizing structure with Brandon/Jordan", {
  x: col1X, y: startY + 0.3, w: 3, h: 0.9, fontSize: 10, fontFace: "Segoe UI", color: "444444"
});
slide.addText("Enablement\n• Copilot CLI Office Hours\n• AI Thirsty Thursday (PostgreSQL + AI)", {
  x: col1X, y: startY + 1.3, w: 3, h: 0.8, fontSize: 10, fontFace: "Segoe UI", color: "444444"
});

// CITRIX (middle column top)
slide.addText("CITRIX", { x: col2X, y: startY, w: 2, h: 0.3, fontSize: 11, fontFace: "Segoe UI", color: "0078D4", bold: true });
slide.addText("• Azure SRE Agent - debugged PagerDuty\n• HTTP/2 & App Gateway roadmap", {
  x: col2X, y: startY + 0.3, w: 3, h: 0.6, fontSize: 10, fontFace: "Segoe UI", color: "444444"
});

// TIBCO (middle column bottom)
slide.addText("TIBCO", { x: col2X, y: startY + 1.1, w: 2, h: 0.3, fontSize: 11, fontFace: "Segoe UI", color: "0078D4", bold: true });
slide.addText("• Building AI workflow demo (BPEL/BPMN)\n• Supports Spotfire Copilot for ASML", {
  x: col2X, y: startY + 1.4, w: 3, h: 0.6, fontSize: 10, fontFace: "Segoe UI", color: "444444"
});

// NCR (right column top)
slide.addText("NCR", { x: col3X, y: startY, w: 2, h: 0.3, fontSize: 11, fontFace: "Segoe UI", color: "0078D4", bold: true });
slide.addText("• Scheduled 1:1 with SSP\n• Coming: BNZ migration planning", {
  x: col3X, y: startY + 0.3, w: 3, h: 0.6, fontSize: 10, fontFace: "Segoe UI", color: "444444"
});

// IBM (right column bottom)
slide.addText("IBM", { x: col3X, y: startY + 1.1, w: 2, h: 0.3, fontSize: 11, fontFace: "Segoe UI", color: "0078D4", bold: true });
slide.addText("• Territory cadence (capacity, Broadcom)\n• Coming: AI accelerated dev opps", {
  x: col3X, y: startY + 1.4, w: 3, h: 0.6, fontSize: 10, fontFace: "Segoe UI", color: "444444"
});

// Divider
slide.addShape("rect", { x: 0.4, y: 3.55, w: 9.2, h: 0.01, fill: { type: "solid", color: "DDDDDD" } });

// UPCOMING section at bottom
slide.addText("UPCOMING", { x: col1X, y: 3.7, w: 2, h: 0.3, fontSize: 11, fontFace: "Segoe UI", color: "0078D4", bold: true });
slide.addText("Mon: IBM Architecture Review, Citrix Strategy, NCR intro  •  Tue: 1:1 Eugene, POD-22 SE Alignment  •  Wed: IBM STU/CSU, Agent Framework OH", {
  x: col1X, y: 4.0, w: 9.2, h: 0.35, fontSize: 9, fontFace: "Segoe UI", color: "555555"
});
slide.addText("→ Complete TIBCO XML workflow demo  •  Heavy AI enablement week (Tech Elevate, Grok/Foundry, AI Path to Production)", {
  x: col1X, y: 4.3, w: 9.2, h: 0.35, fontSize: 9, fontFace: "Segoe UI", color: "555555"
});

// Save
const outputPath = process.argv[2] || "weekly-summary.pptx";
pres.writeFile({ fileName: outputPath })
  .then(() => console.log("Created: " + outputPath))
  .catch(err => console.error(err));
