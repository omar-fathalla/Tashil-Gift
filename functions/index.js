const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/**
 * Escapes HTML entities to prevent XSS in dynamic meta tags
 */
function escapeHtml(str) {
  if (!str) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

/**
 * Cloud Function to generate dynamic OpenGraph link previews for WhatsApp & Social Media
 */
exports.sharePreview = functions.https.onRequest(async (req, res) => {
  try {
    const rawPath = req.path || "/";
    const pathSegments = rawPath.split("/").filter(Boolean);
    const query = req.query || {};

    const routeType = pathSegments[0] || "portal"; // portal, c, p, event, ep, share
    const routeIdentifier = pathSegments[1] || query.event || query.company || "";
    const eventIdParam = query.event || "";

    let companyName = "تسهيل جيفت";
    let eventName = "منظومة إدارة العروض والهدايا الترويجية";
    let companyLogoUrl = "https://tashil-gift.web.app/icons/Icon-512.png";
    let welcomeDesc = "Tashil Gift - Smart Multi-Company Promotion & Validation Platform by Switch Point";
    let isManagerPortal = routeType === "portal" || routeType === "p" || routeType === "ep";

    // 1. Try resolving event from Firestore by ID if available
    let resolvedEvent = null;

    if (eventIdParam) {
      const eventDoc = await db.collection("events").doc(eventIdParam).get();
      if (eventDoc.exists) {
        resolvedEvent = eventDoc.data();
      }
    }

    if (!resolvedEvent && routeIdentifier) {
      // Check if identifier is an event ID
      const eventDoc = await db.collection("events").doc(routeIdentifier).get();
      if (eventDoc.exists) {
        resolvedEvent = eventDoc.data();
      }
    }

    // 2. If not found by event ID, search by companySlug or targetCompany in events collection
    if (!resolvedEvent && routeIdentifier) {
      const cleanSlug = routeIdentifier.toLowerCase();
      const slugQuery = await db
        .collection("events")
        .where("companySlug", "==", cleanSlug)
        .limit(1)
        .get();

      if (!slugQuery.empty) {
        resolvedEvent = slugQuery.docs[0].data();
      }
    }

    // 3. Extract resolved brand information
    if (resolvedEvent) {
      companyName = resolvedEvent.targetCompany || resolvedEvent.companyName || companyName;
      eventName = resolvedEvent.eventName || eventName;
      if (resolvedEvent.companyLogoUrl && resolvedEvent.companyLogoUrl.trim().length > 0) {
        companyLogoUrl = resolvedEvent.companyLogoUrl.trim();
      }
      if (resolvedEvent.welcomeMessage && resolvedEvent.welcomeMessage.trim().length > 0) {
        welcomeDesc = resolvedEvent.welcomeMessage.trim();
      } else if (resolvedEvent.welcomeTitle && resolvedEvent.welcomeTitle.trim().length > 0) {
        welcomeDesc = resolvedEvent.welcomeTitle.trim();
      }
    } else if (query.companyName) {
      companyName = query.companyName;
    }

    if (query.logo) {
      companyLogoUrl = query.logo;
    }

    // 4. Construct rich title and description
    let pageTitle = "";
    let pageDescription = "";

    if (isManagerPortal) {
      pageTitle = `${companyName} • بوابة الشريك | Tashil Gift`;
      pageDescription = `منظومة إدارة ومتابعة الحملات الترويجية والهدايا لشركة ${companyName}`;
    } else {
      pageTitle = `${eventName} (${companyName}) | Tashil Gift`;
      pageDescription = welcomeDesc;
    }

    // 5. Construct client-side SPA redirect URL with hash routing
    let clientRedirectUrl = `https://tashil-gift.web.app/#${rawPath}`;
    if (Object.keys(query).length > 0) {
      const queryString = new URLSearchParams(query).toString();
      clientRedirectUrl = `https://tashil-gift.web.app/#${rawPath}?${queryString}`;
    }

    const escapedTitle = escapeHtml(pageTitle);
    const escapedDesc = escapeHtml(pageDescription);
    const escapedLogo = escapeHtml(companyLogoUrl);

    // Set cache control for performance
    res.set("Cache-Control", "public, max-age=300, s-maxage=600");
    res.set("Content-Type", "text/html; charset=utf-8");

    const html = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapedTitle}</title>
  <meta name="description" content="${escapedDesc}">

  <!-- Open Graph / WhatsApp / Facebook -->
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Tashil Gift">
  <meta property="og:title" content="${escapedTitle}">
  <meta property="og:description" content="${escapedDesc}">
  <meta property="og:image" content="${escapedLogo}">
  <meta property="og:image:secure_url" content="${escapedLogo}">
  <meta property="og:image:alt" content="${escapedTitle}">
  <meta property="og:image:width" content="600">
  <meta property="og:image:height" content="600">

  <!-- Twitter Card -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapedTitle}">
  <meta name="twitter:description" content="${escapedDesc}">
  <meta name="twitter:image" content="${escapedLogo}">

  <!-- Instant Client-Side SPA Redirect for Browsers -->
  <meta http-equiv="refresh" content="0; url=${clientRedirectUrl}">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      background: #f8fafc;
      color: #1e293b;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
      padding: 20px;
      text-align: center;
      box-sizing: border-box;
    }
    .card {
      background: white;
      border-radius: 20px;
      padding: 32px;
      box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.1), 0 8px 10px -6px rgba(0, 0, 0, 0.1);
      max-width: 440px;
      width: 100%;
    }
    .logo {
      width: 80px;
      height: 80px;
      object-fit: contain;
      border-radius: 16px;
      margin-bottom: 16px;
    }
    .spinner {
      width: 36px;
      height: 36px;
      border: 3.5px solid #e2e8f0;
      border-top-color: #6366f1;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 20px auto 10px;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
    a {
      color: #6366f1;
      text-decoration: none;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <div class="card">
    <img src="${escapedLogo}" alt="${escapedTitle}" class="logo" onerror="this.src='https://tashil-gift.web.app/icons/Icon-192.png'">
    <h3 style="margin: 0 0 8px 0;">${escapedTitle}</h3>
    <p style="margin: 0 0 16px 0; color: #64748b; font-size: 14px;">${escapedDesc}</p>
    <div class="spinner"></div>
    <p style="font-size: 13px; color: #94a3b8; margin: 12px 0 0 0;">
      جاري التحويل تلقائياً... <br>
      <a href="${clientRedirectUrl}">اضغط هنا إذا لم يتم تحويلك</a>
    </p>
  </div>
  <script>
    window.location.replace("${clientRedirectUrl}");
  </script>
</body>
</html>`;

    res.status(200).send(html);
  } catch (error) {
    console.error("Error generating share preview:", error);
    // Graceful fallback to static Flutter web SPA
    res.redirect("/index.html");
  }
});
