#!/usr/bin/env python3
"""Build the Do. launch plan as a designed PDF.

Styled as the app is: paper #f7f3e9, rust #c8553d, ink #2b2620, and the app's
own serif (Iowan Old Style) for headings, so the document looks like the thing
it is about.
"""
import os
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, Frame, Image, KeepTogether,
                                NextPageTemplate, PageBreak, PageTemplate,
                                Paragraph, Spacer, Table, TableStyle)

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, "img")
OUT = os.path.join(HERE, "Do-launch-plan.pdf")

PAPER = colors.HexColor("#f7f3e9")
RUST = colors.HexColor("#c8553d")
INK = colors.HexColor("#2b2620")
SOFT = colors.HexColor("#6b6259")
FAINT = colors.HexColor("#a89f93")
RULE = colors.HexColor("#e2dbcb")
CARD = colors.HexColor("#fdfbf6")
GREEN = colors.HexColor("#4a7c59")

IOWAN = "/System/Library/Fonts/Supplemental/Iowan Old Style.ttc"
pdfmetrics.registerFont(TTFont("Iowan", IOWAN, subfontIndex=0))
pdfmetrics.registerFont(TTFont("Iowan-Bold", IOWAN, subfontIndex=1))
pdfmetrics.registerFont(TTFont("Iowan-It", IOWAN, subfontIndex=2))

W, H = A4
M = 20 * mm

S = {}
S["h1"] = ParagraphStyle("h1", fontName="Iowan-Bold", fontSize=23, leading=27,
                         textColor=INK, spaceAfter=3, spaceBefore=0)
S["kicker"] = ParagraphStyle("kicker", fontName="Helvetica-Bold", fontSize=7.5,
                             leading=10, textColor=RUST, spaceAfter=7,
                             tracking=1)
S["h2"] = ParagraphStyle("h2", fontName="Iowan-Bold", fontSize=13.5, leading=17,
                         textColor=INK, spaceBefore=13, spaceAfter=5)
S["h3"] = ParagraphStyle("h3", fontName="Helvetica-Bold", fontSize=9,
                         leading=12, textColor=RUST, spaceBefore=9, spaceAfter=3)
S["body"] = ParagraphStyle("body", fontName="Helvetica", fontSize=9.3,
                           leading=13.6, textColor=INK, spaceAfter=7,
                           alignment=TA_LEFT)
S["small"] = ParagraphStyle("small", fontName="Helvetica", fontSize=8,
                            leading=11.4, textColor=SOFT, spaceAfter=5)
S["cap"] = ParagraphStyle("cap", fontName="Helvetica-Oblique", fontSize=7.6,
                          leading=10.5, textColor=SOFT, spaceAfter=3,
                          spaceBefore=3)
S["quote"] = ParagraphStyle("quote", fontName="Iowan-It", fontSize=11,
                            leading=15.5, textColor=RUST, spaceAfter=8,
                            leftIndent=10)
S["bullet"] = ParagraphStyle("bullet", parent=S["body"], leftIndent=12,
                             bulletIndent=2, spaceAfter=4)
S["cover_t"] = ParagraphStyle("cover_t", fontName="Iowan-Bold", fontSize=66,
                              leading=68, textColor=INK)
S["cover_s"] = ParagraphStyle("cover_s", fontName="Iowan", fontSize=16,
                              leading=22, textColor=SOFT)
S["cover_m"] = ParagraphStyle("cover_m", fontName="Helvetica", fontSize=8.5,
                              leading=13, textColor=FAINT)


def page_bg(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(PAPER)
    canvas.rect(0, 0, W, H, stroke=0, fill=1)
    # the rust bar from the icon, across the top of every page
    canvas.setFillColor(RUST)
    canvas.rect(0, H - 6 * mm, W, 6 * mm, stroke=0, fill=1)
    # dotted grid, as in the icon
    canvas.setFillColor(colors.HexColor("#ece6d9"))
    step = 11 * mm
    y = 14 * mm
    while y < H - 8 * mm:
        x = 10 * mm
        while x < W - 6 * mm:
            canvas.circle(x, y, 0.45, stroke=0, fill=1)
            x += step
        y += step
    canvas.setFont("Helvetica", 7)
    canvas.setFillColor(FAINT)
    canvas.drawString(M, 11 * mm, "Do.  -  launch plan")
    canvas.drawRightString(W - M, 11 * mm, "page %d" % (doc.page - 1))
    canvas.restoreState()


def cover_bg(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(PAPER)
    canvas.rect(0, 0, W, H, stroke=0, fill=1)
    canvas.setFillColor(RUST)
    canvas.rect(0, H - 14 * mm, W, 14 * mm, stroke=0, fill=1)
    canvas.setFillColor(colors.HexColor("#ece6d9"))
    step = 11 * mm
    y = 14 * mm
    while y < H - 16 * mm:
        x = 10 * mm
        while x < W - 6 * mm:
            canvas.circle(x, y, 0.5, stroke=0, fill=1)
            x += step
        y += step
    canvas.restoreState()


def tbl(data, widths, head=True, small=False, align=None):
    # Cells MUST be Paragraphs: ReportLab does not wrap plain strings in a
    # table, it just lets them run off the page edge.
    fs = 7.6 if small else 8.3
    align = align or {}
    from reportlab.lib.enums import TA_RIGHT
    def cell_style(name, bold, colour, a):
        return ParagraphStyle(
            name, fontName="Helvetica-Bold" if bold else "Helvetica",
            fontSize=fs, leading=fs * 1.33, textColor=colour,
            alignment=TA_RIGHT if a == "RIGHT" else TA_LEFT)
    body = []
    for r, row in enumerate(data):
        out = []
        for c, val in enumerate(row):
            if isinstance(val, Paragraph) or not isinstance(val, str):
                out.append(val)
                continue
            is_head = head and r == 0
            st_ = cell_style("c%d_%d" % (r, c), is_head,
                             colors.white if is_head else INK,
                             align.get(c))
            out.append(Paragraph(val, st_))
        body.append(out)
    t = Table(body, colWidths=widths, hAlign="LEFT")
    st = [
        ("TEXTCOLOR", (0, 0), (-1, -1), INK),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("LINEBELOW", (0, 0), (-1, -2), 0.4, RULE),
        ("BACKGROUND", (0, 0), (-1, -1), CARD),
    ]
    if head:
        st += [
            ("BACKGROUND", (0, 0), (-1, 0), RUST),
            ("LINEBELOW", (0, 0), (-1, 0), 0, RUST),
        ]
    t.setStyle(TableStyle(st))
    return t


def pic(name, width_mm, caption=None):
    path = os.path.join(IMG, name)
    from PIL import Image as PILImage
    iw, ih = PILImage.open(path).size
    w = width_mm * mm
    h = w * ih / iw
    out = [Image(path, width=w, height=h)]
    if caption:
        out.append(Paragraph(caption, S["cap"]))
    return out


def P(t, st="body"):
    return Paragraph(t, S[st])


def bullets(items):
    return [Paragraph(x, S["bullet"], bulletText="•") for x in items]


story = []
A = story.append

# ───────────────────────── cover ─────────────────────────
A(Spacer(1, 30 * mm))
A(Image(os.path.join(IMG, "icon.png"), width=34 * mm, height=34 * mm))
A(Spacer(1, 12 * mm))
A(P("Do.", "cover_t"))
A(Spacer(1, 4 * mm))
A(P("The to-do app that was designed on a folding phone<br/>"
    "from the first line of code.", "cover_s"))
A(Spacer(1, 16 * mm))
A(tbl([
    ["Product", "Do. - iOS, paid once"],
    ["Price", "USD 9.99 worldwide  /  EGP 99 in Egypt"],
    ["Owner", "Ahmed Hassaan"],
    ["Status", "Running on device, build 2026-11-09-1612"],
    ["Date", "9 November 2026"],
], [32 * mm, 95 * mm], head=False))
A(Spacer(1, 18 * mm))
A(P("This plan is ordered by the risks that actually bite, not by the work "
    "that feels exciting. Section 2 is the one that can stop everything else.",
    "small"))
A(NextPageTemplate("body"))
A(PageBreak())

# ───────────────────────── 1. where we are ─────────────────────────
A(P("SECTION ONE", "kicker"))
A(P("Where the product actually is", "h1"))
A(Spacer(1, 4 * mm))
A(P("Do. is not a prototype. It is a working app, installed and running on a "
    "folding iPhone today, built from a single HTML file wrapped in a native "
    "iOS shell. What follows is what exists, not what is planned."))

A(P("Working today", "h2"))
A(tbl([
    ["Capability", "State", "Evidence"],
    ["Task lists, dates, notes, scheduled tasks",
     "Done", "Four lists, natural-language dates, 74 parser tests passing"],
    ["Natural date entry",
     "Done", "'call mum tomorrow 6pm' sets the date itself"],
    ["Works offline, no account needed",
     "Done", "All storage local; sync is opt-in"],
    ["Local notifications",
     "Done", "Scheduled by iOS, fire with the app closed, verified on the lock screen"],
    ["Home screen widgets",
     "Done", "Three WidgetKit widgets reading the app's own storage"],
    ["Folding layout",
     "Done", "Verified at eight widths by an automated harness"],
    ["Installed on device",
     "Done", "Signed and running on iPhone19,4, iOS 27.3"],
    ["App Store listing",
     "Not started", "Needs the work in sections 2 and 6"],
], [52 * mm, 18 * mm, 72 * mm]))

A(P("The engineering discipline already in place", "h2"))
A(P("This matters for a paid product, because it is what keeps a one-person "
    "app from breaking in public:"))
for b in bullets([
    "<b>A preflight that blocks releases.</b> It refuses to stamp a build if "
    "the script will not compile, if ids are missing or duplicated, if the "
    "stylesheet is unbalanced, or if the build id disagrees across files.",
    "<b>A browser harness</b> checking layout containment, core flows and "
    "search at every width that matters.",
    "<b>74 parser tests</b> extracted from the shipping file by marker comment, "
    "so the tested code is always the shipped code.",
    "<b>An error dot</b> on the device: uncaught errors are recorded and shown, "
    "because the failure mode of this app is silence.",
]):
    A(b)
A(PageBreak())

# ───────────────────────── 2. the gate ─────────────────────────
A(P("SECTION TWO", "kicker"))
A(P("The gate: App Review, Guideline 4.2", "h1"))
A(Spacer(1, 3 * mm))
A(P("<b>This is the only thing in this document that can stop the whole "
    "plan.</b> Everything else is a choice; this is a yes or no from Apple."))
A(P("Do. is a bundled web layer in a native shell. Apple does not ban that. "
    "It rejects apps that are <i>no more than a repackaged website</i>, under "
    "Guideline 4.2, Minimum Functionality. A reviewer decides which one you "
    "are in about ninety seconds."))

A(P("We currently look like a website in one visible place", "h3"))
A(P("The due date field is a raw web control:"))
A(Paragraph('<font face="Courier" size="9" color="#c8553d">'
            '&lt;input type="datetime-local"&gt;</font>', S["body"]))
A(P("which is why the app shows <b>dd/mm/yyyy, --:--</b> instead of an iOS "
    "date picker. That grey web control, sitting in an otherwise carefully "
    "made screen, is precisely the signal reviewers are trained to look for: "
    "<i>web content that is not formatted for iOS</i>. It is also simply "
    "worse than the native control, so fixing it is not a compliance chore."))

A(P("What counts in our favour", "h3"))
A(tbl([
    ["In our favour", "Why it matters"],
    ["The web code is bundled, not fetched from a server",
     "A locally bundled hybrid app is a different thing to a webview pointed at a URL"],
    ["Real local notifications",
     "Scheduled by iOS, fire offline with the app closed - a website cannot do this"],
    ["Real WidgetKit widgets",
     "Three of them, reading the app's own App Group storage"],
    ["Genuine offline behaviour",
     "No browser error page, no spinner, no login that forgets you"],
], [58 * mm, 84 * mm]))

A(P("What I would add before submitting", "h3"))
A(P("Each of these is something a website cannot do, which is the actual "
    "test. Items 1 to 4 are the minimum I would submit on; 5 to 7 are what "
    "make it worth USD 9.99 rather than merely approvable."))
A(tbl([
    ["#", "Addition", "Effort", "Why"],
    ["1", "Native date and time picker", "1 day", "Removes the one visible flaw"],
    ["2", "App Intents and Siri", "2 days", "'Add buy milk to Personal'; also Shortcuts and the Action button"],
    ["3", "Spotlight indexing", "1 day", "Tasks findable from the iPhone home screen search"],
    ["4", "Share extension", "1 day", "Share a message or page, it becomes a task"],
    ["5", "Live Activity", "2 days", "A running scheduled task counting down in the Dynamic Island"],
    ["6", "Focus filters", "1 day", "Work Focus shows Business only"],
    ["7", "Native swipe actions and haptics", "1 day", "The list feels like a list, not a page"],
], [8 * mm, 46 * mm, 16 * mm, 72 * mm]))

A(P("The deeper question, stated once", "h3"))
A(P("A web layer is a ceiling on how native this app can ever feel, and at "
    "USD 9.99 it competes with apps that are native to the bone. The "
    "alternative is rebuilding the interface in SwiftUI over the same model: "
    "weeks of work, and it throws away something that works beautifully today "
    "and deploys in sixty seconds. <b>My recommendation is not to do it "
    "yet.</b> Ship the hardened hybrid, find out whether people buy it, and "
    "let revenue rather than taste decide. But go in knowing the ceiling is "
    "there."))
A(PageBreak())

# ───────────────────────── 3. the fold ─────────────────────────
A(P("SECTION THREE", "kicker"))
A(P("What you are actually selling", "h1"))
A(Spacer(1, 3 * mm))
A(P("Not 'a to-do app'. There are thousands, and Apple gives Reminders away "
    "for nothing."))
A(P("You are selling the only to-do app designed on a folding iPhone from "
    "the first line of CSS.", "quote"))
A(P("That claim is true, it is unusual, and - crucially - it is <b>visual</b>. "
    "It can be demonstrated in fifteen seconds without a word of explanation, "
    "which is what makes it marketable in a way that 'better task management' "
    "never is."))

A(P("Measured on the actual device", "h2"))
A(tbl([
    ["State", "Viewport", "What the app does"],
    ["Folded", "373 x 603", "One list; card fan to switch; the fan tucks away as you read"],
    ["Unfolded", "867 x 594", "Three columns, side by side"],
    ["Unfolded, wide", "1114 x 594", "Four columns including Scheduled tasks"],
], [26 * mm, 26 * mm, 90 * mm]))
A(P("No reload. No separate iPad build. No 'optimised for' asterisk. The "
    "layout is built on containment rather than pixel breakpoints, which is "
    "why it survives the hinge. It is verified at 320, 373, 430, 718, 900, "
    "1114, 1280 and 1440 by a harness that runs on every change.", "small"))
A(Spacer(1, 3 * mm))
for x in pic("folded.jpg", 52,
             "Folded, 373 x 603. One list, the card fan above it."):
    A(x)
A(PageBreak())

A(P("SECTION THREE, CONTINUED", "kicker"))
A(P("The unfold", "h1"))
A(Spacer(1, 3 * mm))
A(P("This is the campaign. Everything in section seven is about finding the "
    "most beautiful way to film the transition between these two pages."))
for x in pic("unfolded-867.jpg", 150,
             "Unfolded, 867 x 594. The same app, the same instant, three columns."):
    A(x)
A(Spacer(1, 4 * mm))
for x in pic("unfolded-1114.jpg", 150,
             "Unfolded wide, 1114 x 594. Scheduled tasks joins as a fourth column."):
    A(x)
A(PageBreak())

# ───────────────────────── 4. name and brand ─────────────────────────
A(P("SECTION FOUR", "kicker"))
A(P("Name and brand", "h1"))
A(Spacer(1, 3 * mm))
A(P("<b>Do.</b> - confirmed. The mark already exists and is already good: "
    "Iowan Old Style Bold on paper, a rust full stop, a rust bar across the "
    "top, a faint dotted grid behind. It reads as stationery rather than "
    "software, which is the whole personality."))
A(tbl([
    ["Token", "Value", "Use"],
    ["Paper", "#f7f3e9", "Every background, app and marketing"],
    ["Rust", "#c8553d", "The full stop, the bar, primary actions"],
    ["Ink", "#2b2620", "All body text"],
    ["Ink soft", "#6b6259", "Secondary text"],
    ["Serif", "Iowan Old Style", "The wordmark and all headings"],
], [24 * mm, 36 * mm, 82 * mm]))
A(P("Practical warnings on the name", "h3"))
for b in bullets([
    "<b>'Do' alone is almost certainly taken on the App Store</b> and is close "
    "to unsearchable. The display name should carry a qualifier: <i>Do. - "
    "Lists that fold</i>, or similar. The icon and the wordmark stay 'Do.'",
    "Check availability in App Store Connect before anything is printed, "
    "filmed or registered. Reserving the name is free and takes minutes.",
    "Buy the domain at the same time, and the social handles, even if unused. "
    "This is the cheapest insurance in the plan.",
]):
    A(b)
A(PageBreak())

# ───────────────────────── 5. price ─────────────────────────
A(P("SECTION FIVE", "kicker"))
A(P("Price and what reaches you", "h1"))
A(Spacer(1, 3 * mm))
A(P("Paid up front, one purchase, no subscription, no in-app purchases. It "
    "suits the product's character and it is what you asked for."))

A(P("Enrol in the Small Business Program before the first sale", "h3"))
A(P("It is <b>not automatic</b>. It takes Apple's commission from 30% to 15% "
    "for developers under USD 1M a year, which is you. Forgetting costs you "
    "USD 1.50 on every single copy, forever."))
A(tbl([
    ["", "USD 9.99", "EGP 99"],
    ["Apple takes at 15% (Small Business Program)", "1.50", "15"],
    ["You receive", "8.49", "84"],
    ["Apple takes at 30% (if you forget to enrol)", "3.00", "30"],
    ["You receive", "6.99", "69"],
], [84 * mm, 29 * mm, 29 * mm], align={1: "RIGHT", 2: "RIGHT"}))
A(P("Figures before local taxes, which Apple collects and remits.", "cap"))

A(P("Regional pricing is supported", "h3"))
A(P("Apple lets you set a base price and override it per storefront, so USD "
    "9.99 worldwide with EGP 99 in Egypt is an ordinary configuration, not a "
    "workaround. <b>Unverified:</b> I could not confirm Apple's exact EGP "
    "price points from here - 99 may have to round to the nearest available "
    "point. Check the price grid in App Store Connect."))

A(P("The honest risk on price", "h3"))
A(P("USD 9.99 once, against a free and pre-installed Reminders app, is a hard "
    "sell on features alone. It works for the premium apps in this category "
    "because their craft is undeniable in the first three seconds. That is "
    "the bar - and it is the strongest argument for doing section two "
    "properly rather than minimally. One-time pricing also means no recurring "
    "revenue to fund years of iOS updates; that is a real trade you are "
    "choosing deliberately."))

A(P("What it takes to break even", "h3"))
A(tbl([
    ["Year one cost to recover", "Copies at USD 8.49 net", "Or copies at EGP 84 net"],
    ["USD 99 (minimum: Apple only)", "12", "~60"],
    ["USD 128 (Apple + domain)", "16", "~78"],
    ["USD 428 (with a freelance editor for the film)", "51", "~250"],
], [58 * mm, 42 * mm, 42 * mm], align={1: "RIGHT", 2: "RIGHT"}))
A(P("EGP conversions are indicative only and move with the exchange rate.",
    "cap"))
A(PageBreak())

# ───────────────────────── 6. hosting ─────────────────────────
A(P("SECTION SIX", "kicker"))
A(P("Where it is hosted, and what that costs", "h1"))
A(Spacer(1, 3 * mm))
A(P("There are four separate things people mean by 'hosting' here, and they "
    "have very different answers."))

A(P("1. The app itself - nothing to host", "h3"))
A(P("Apple hosts and delivers the binary. There is no server, no bandwidth "
    "bill, no scaling problem, however many copies sell. This is the whole "
    "point of selling through the App Store and it is already paid for by the "
    "USD 99 membership."))

A(P("2. The marketing site - free", "h3"))
A(tbl([
    ["Option", "Cost", "Notes"],
    ["GitHub Pages", "Free", "Already in use for the web app; custom domains and HTTPS included"],
    ["Cloudflare Pages", "Free", "Faster globally, better in Egypt, free tier is generous"],
    ["Netlify / Vercel", "Free tier", "More than needed for a one-page site"],
], [34 * mm, 20 * mm, 88 * mm]))
A(P("<b>Recommendation: Cloudflare Pages</b> for the marketing site, because "
    "its edge network is noticeably better in the Middle East than GitHub's, "
    "and the free tier covers everything a landing page and a privacy policy "
    "will ever need."))

A(P("3. Sync - and this is the important decision", "h3"))
A(P("The app works entirely offline and needs no backend at all. Sync is "
    "optional. But if you want it across devices, the choice matters more "
    "than it looks:"))
A(tbl([
    ["Option", "Cost", "Reality"],
    ["Apple CloudKit", "Free",
     "Private data counts against each user's own iCloud quota, not yours. No server, no ops, no bill that grows with success. iOS only."],
    ["Supabase free tier", "Free",
     "500 MB database, 2 projects - but free projects PAUSE after 7 days idle. Unacceptable for a paid app."],
    ["Supabase Pro", "USD 25/mo",
     "USD 300/yr. Needed the moment you have real users on the current design. Next tier up is a cliff at USD 599/mo."],
], [34 * mm, 22 * mm, 86 * mm]))
A(P("<b>Recommendation: move sync to CloudKit.</b> For an iOS-only paid app "
    "this is close to a free lunch - Apple carries the storage against each "
    "user's own iCloud allowance, there is no server for you to run, and the "
    "privacy story becomes genuinely excellent: your data never touches a "
    "machine the developer controls. It also removes a USD 300/year fixed "
    "cost and a scaling risk. The work is roughly three to four days."))
A(P("Keep the existing Supabase path alive for the web version, which "
    "CloudKit cannot serve.", "small"))

A(P("4. Domain, email, video, analytics", "h3"))
A(tbl([
    ["Item", "Cost per year", "Notes"],
    ["Domain (.com)", "USD 10 - 15", "Buy early; cheapest insurance in this plan"],
    ["Domain (.app)", "USD 14 - 20", "HTTPS enforced by the registry, which suits us"],
    ["Email on the domain", "Free", "Cloudflare Email Routing forwards to your existing inbox"],
    ["Video hosting", "Free", "YouTube and Vimeo free tiers; App Store previews are hosted by Apple"],
    ["Analytics", "Free, or ~USD 108", "None is a legitimate choice and fits the privacy story. Plausible is ~USD 9/mo if you want it"],
], [36 * mm, 28 * mm, 78 * mm]))
A(PageBreak())

# ───────────────────────── 7. total cost ─────────────────────────
A(P("SECTION SEVEN", "kicker"))
A(P("The whole cost, year one", "h1"))
A(Spacer(1, 3 * mm))
A(P("Three honest scenarios. The difference between them is almost entirely "
    "how much of the video work you buy rather than do."))
A(tbl([
    ["Item", "Lean", "Sensible", "Full"],
    ["Apple Developer Program", "99", "99", "99"],
    ["Domain", "0", "14", "14"],
    ["Marketing site hosting", "0", "0", "0"],
    ["Sync (CloudKit)", "0", "0", "0"],
    ["Email on domain", "0", "0", "0"],
    ["Video editor (freelance, the hero film)", "0", "300", "800"],
    ["Music licence", "0", "0", "60"],
    ["Analytics", "0", "0", "108"],
    ["Paid launch promotion", "0", "0", "300"],
    ["TOTAL, year one (USD)", "99", "413", "1,381"],
    ["Copies to break even, at USD 8.49 net", "12", "49", "163"],
], [68 * mm, 22 * mm, 24 * mm, 22 * mm],
    align={1: "RIGHT", 2: "RIGHT", 3: "RIGHT"}))
A(P("If you keep sync on Supabase Pro instead of moving to CloudKit, add "
    "USD 300 a year to every column, and 36 more copies to break even.",
    "cap"))

A(P("What recurs after year one", "h3"))
A(tbl([
    ["Recurring", "Amount"],
    ["Apple Developer Program", "USD 99 / year"],
    ["Domain", "USD 10 - 20 / year"],
    ["Everything else at the lean tier", "USD 0"],
], [68 * mm, 40 * mm], align={1: "RIGHT"}))
A(P("<b>The floor is USD 99 a year.</b> That is the honest answer to 'what "
    "does it cost to run': twelve copies sold pays for the year, and "
    "everything after that is yours. This is an unusually cheap product to "
    "operate, because the app needs no server and the marketing site is "
    "static."))

A(P("Not a cost, but a real budget: your time", "h3"))
A(P("The work in section eight is roughly three to four weeks of focused "
    "effort before submission. That is the actual investment. The money is "
    "almost a rounding error by comparison."))
A(PageBreak())

# ───────────────────────── 8. plan ─────────────────────────
A(P("SECTION EIGHT", "kicker"))
A(P("The plan, in order", "h1"))
A(Spacer(1, 3 * mm))
A(tbl([
    ["Phase", "Who", "Time", "What"],
    ["0. Enrol", "You", "1-7 days",
     "Apple Developer Program, ONE Apple ID. Enrol in the Small Business Program the same day. Reserve the app name."],
    ["1. Native hardening", "Me", "~1 week",
     "Items 1-4 from section two, each behind the existing NATIVE guard so the web version is untouched."],
    ["2. The fold, deliberately", "Me", "~2 days",
     "The layout already adapts; make it perform. Tune the transition, make state survive the hinge, test half-open. This is the footage."],
    ["3. Sync on CloudKit", "Me", "3-4 days",
     "Removes the only recurring infrastructure cost and improves the privacy story. Optional for v1."],
    ["4. Beta", "Both", "~1 week",
     "TestFlight, 10-20 people, at least three on folding hardware. Watch where they stop."],
    ["5. Store assets", "Both", "~3 days",
     "Screenshots, preview videos, description, keywords, privacy label."],
    ["6. Submit", "Me", "1-3 days review",
     "With review notes explaining the native surface explicitly."],
    ["7. Launch and film", "Both", "ongoing", "Section nine."],
], [30 * mm, 14 * mm, 20 * mm, 78 * mm], small=True))
A(Spacer(1, 3 * mm))
A(P("<b>Realistic first submission: four to six weeks from the day you "
    "enrol</b>, assuming the app keeps working while we add to it - which is "
    "what the preflight and the harness are for."))

A(P("The 7-day expiry dies on day one", "h3"))
A(P("A side effect worth naming: the moment we sign with the paid team, "
    "provisioning profiles go from 7 days to 365. The weekly reinstall you "
    "asked to be rid of disappears as soon as you enrol - before any of the "
    "rest of this plan happens."))
A(PageBreak())

# ───────────────────────── 9. video ─────────────────────────
A(P("SECTION NINE", "kicker"))
A(P("The films", "h1"))
A(Spacer(1, 3 * mm))
A(P("Three different things for three different places. Do not try to make "
    "one film do all three jobs."))

A(P("A. The hero film - 60 to 75 seconds", "h2"))
A(P("For the site, X, LinkedIn, YouTube. One idea: <i>the app is the shape of "
    "your phone.</i>"))
A(tbl([
    ["#", "Shot", "Note"],
    ["1", "Black. A folded phone, screen off, on a paper-coloured surface.",
     "Match #f7f3e9. The brand is a colour before it is a logo"],
    ["2", "A thumb wakes it. One list. A task gets ticked.",
     "Real hands, real speed. Never speed up the footage"],
    ["3", "Push the list up - the card fan tucks away, the list fills the phone.",
     "The detail that says somebody thought about this"],
    ["4", "THE UNFOLD. One column becomes three.",
     "ONE CONTINUOUS TAKE. A cut is what makes viewers assume you hid a reload"],
    ["5", "Hold on three columns. Drag a task between lists.", ""],
    ["6", "Fold it shut mid-task. Open again - exactly where you were.",
     "Proof it is one app, not two"],
    ["7", "Lock screen. A reminder arrives.",
     "'It tells you. It doesn't wait to be checked'"],
    ["8", "Home screen, the widget, the icon. Title card.", ""],
], [8 * mm, 66 * mm, 68 * mm], small=True))
A(Spacer(1, 2 * mm))
A(P("<b>Shot 4 is the whole film. Budget half your shooting time for it.</b>"))
for b in bullets([
    "<b>Voice:</b> none, or one line at the end. The typography is the brand. "
    "Let the screen talk.",
    "<b>Music:</b> a single piano or guitar motif, with one note landing "
    "exactly on the unfold.",
    "<b>Capture:</b> screen recording comes off the device over the cable - "
    "perfectly clean pixels, but no hands. The physical unfold needs a camera. "
    "So shoot both and composite: camera for the hinge, screen capture tracked "
    "onto the panel. This is the one job worth paying a freelance editor for.",
]):
    A(b)

A(P("B. App Store preview videos - up to three, 15 to 30 seconds", "h2"))
A(P("A different discipline: no hands, no voiceover, autoplay muted, and the "
    "first second has to land. Apple requires real device capture."))
A(tbl([
    ["#", "Subject", "Length"],
    ["1", "The fold. Folded, unfolded, three columns. This is the one.", "15s"],
    ["2", "Capture speed. Type 'call mum tomorrow 6pm'; the date sets itself.", "20s"],
    ["3", "It tells you. Lock screen reminder, then the home screen widget.", "20s"],
], [8 * mm, 108 * mm, 18 * mm], small=True))

A(P("C. Short form - 7 to 15 seconds", "h2"))
A(P("TikTok, Reels, Shorts. One idea each, hook in the first half second, "
    "caption burned in."))
for b in bullets([
    "<i>'Your to-do app wasn't made for this phone. Mine was.'</i> then the unfold.",
    "<i>'One list. Unfold. Three.'</i> Nothing else.",
    "<i>'I wrote this for myself in a single HTML file.'</i> then the unfold. "
    "The builder story - this is the one developers share.",
    "<i>'Watch what happens when I close it mid-task.'</i> Fold, open, still there.",
]):
    A(b)
A(P("Post the unfold on its own, repeatedly, with different captions. It is "
    "the only asset that needs no explanation.", "small"))
A(PageBreak())

# ───────────────────────── 10. listing ─────────────────────────
A(P("SECTION TEN", "kicker"))
A(P("The store listing", "h1"))
A(Spacer(1, 3 * mm))
A(tbl([
    ["Element", "Guidance"],
    ["Name", "'Do.' as the mark, with a qualifier for search: 'Do. - Lists that fold'. Check availability before printing anything."],
    ["Subtitle (30 chars)", "The fold, or the speed. Not both."],
    ["Keywords", "fold, folding, todo, tasks, reminders, widget, offline, privacy, notes"],
    ["Screenshot 1", "Three columns on the unfolded screen. It is the only screenshot in the category that looks like that, so it must be first."],
    ["Screenshots 2-5", "Folded list, the reminder on the lock screen, the widget, natural date entry."],
    ["Description", "First two lines are all most people read. Lead with the fold."],
    ["Privacy label", "A genuine advantage: nothing leaves the device unless you turn sync on, no account required, no analytics. Say so prominently."],
    ["Review notes", "Explicitly list the native surface: notifications, widgets, App Intents, Spotlight, share extension. Make the reviewer's job easy."],
], [30 * mm, 112 * mm], small=True))

A(P("Launch sequence", "h2"))
for b in bullets([
    "<b>Before approval:</b> site live, film cut, handles registered, 20 beta "
    "testers briefed and ready to post on day one.",
    "<b>Day one:</b> the unfold clip everywhere at once. Product Hunt. "
    "Hacker News with the builder angle - 'I built my to-do app as one HTML "
    "file and wrapped it for the folding iPhone' is a title that gets read.",
    "<b>Week one:</b> reply to everything. Pitch the fold angle to iOS "
    "journalists and folding-phone reviewers; they need folding-specific "
    "software to write about and there is very little of it.",
    "<b>Egypt specifically:</b> the EGP 99 price is a genuine local story. "
    "Egyptian tech press and communities respond to a local developer shipping "
    "globally at a fair local price.",
]):
    A(b)
A(PageBreak())

# ───────────────────────── 11. risks ─────────────────────────
A(P("SECTION ELEVEN", "kicker"))
A(P("Risks, and what I could not verify", "h1"))
A(Spacer(1, 3 * mm))
A(tbl([
    ["Risk", "Severity", "What reduces it"],
    ["Rejected under Guideline 4.2 as a repackaged website", "High",
     "Section two, items 1-4, and explicit review notes"],
    ["USD 9.99 does not convert against free Reminders", "High",
     "Craft in the first three seconds; the fold as a reason to look"],
    ["One-time price funds no future development", "Medium",
     "Accepted deliberately. Revisit with a paid major version, not a subscription"],
    ["Folding iPhone is a small market today", "Medium",
     "The app is excellent on ordinary iPhones too; the fold is the hook, not the product"],
    ["A single HTML file is a ceiling on native feel", "Medium",
     "Revisit after launch, funded by revenue"],
    ["Solo developer, no redundancy", "Medium",
     "The preflight, harness and tests exist precisely for this"],
], [52 * mm, 18 * mm, 72 * mm], small=True))

A(P("Stated plainly, so nobody builds on sand", "h2"))
for b in bullets([
    "<b>Apple's exact EGP price points.</b> Per-storefront pricing exists; "
    "whether exactly 99 is selectable I could not confirm. Check App Store "
    "Connect.",
    "<b>The folding iPhone's official name and specifications.</b> Every "
    "search result was rumour-grade and they contradicted each other. Use "
    "Apple's own name for the device in all copy. The screen numbers in "
    "section three come from the device in your hand, which is better "
    "evidence than any article.",
    "<b>CloudKit's current free limits for public data.</b> Apple no longer "
    "publishes them clearly. Private data - which is what this app stores - "
    "counts against each user's own iCloud quota and costs the developer "
    "nothing. That part is documented by Apple.",
    "<b>Commission rates may move.</b> There is live litigation that could "
    "change App Store rates. 15% under the Small Business Program is what is "
    "documented today.",
    "<b>Review outcomes are never certain.</b> Section two reduces the risk. "
    "It cannot eliminate it.",
]):
    A(b)
A(PageBreak())

# ───────────────────────── 12. next ─────────────────────────
A(P("SECTION TWELVE", "kicker"))
A(P("The first three things", "h1"))
A(Spacer(1, 6 * mm))
A(tbl([
    ["", "Who", "Action"],
    ["1", "You",
     "Enrol in the Apple Developer Program on ONE Apple ID, and enrol in the Small Business Program in App Store Connect the same day. Reserve the app name while you are there. This also kills the 7-day expiry immediately."],
    ["2", "Me",
     "Replace the web date input with a native picker, and add App Intents. That is the one visible flaw and the strongest native signal, in that order."],
    ["3", "Both",
     "Shoot the unfold once, roughly, on a phone, before any polish. If fifteen seconds of that does not make someone say 'wait, do that again', the positioning is wrong - and we would rather learn it in week one than week six."],
], [8 * mm, 16 * mm, 118 * mm]))
A(Spacer(1, 12 * mm))
A(P("The product is real, it runs, and the thing that makes it unusual is "
    "already built and already verified. What stands between here and a "
    "listing is about three weeks of native surface, one very good fifteen "
    "second clip, and USD 99.", "quote"))
A(Spacer(1, 10 * mm))
A(P("Prepared 9 November 2026. Figures marked unverified should be checked "
    "in App Store Connect before anything depends on them.", "small"))

doc = BaseDocTemplate(OUT, pagesize=A4,
                      leftMargin=M, rightMargin=M,
                      topMargin=18 * mm, bottomMargin=18 * mm,
                      title="Do. - launch plan",
                      author="Ahmed Hassaan",
                      subject="App Store launch plan for Do.")
frame = Frame(M, 16 * mm, W - 2 * M, H - 34 * mm, id="f")
doc.addPageTemplates([
    PageTemplate(id="cover", frames=[frame], onPage=cover_bg),
    PageTemplate(id="body", frames=[frame], onPage=page_bg),
])
doc.build(story)
print("wrote", OUT)
print("size: %.1f KB" % (os.path.getsize(OUT) / 1024))
