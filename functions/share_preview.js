"use strict";

/**
 * OpenGraph preview for campaign links.
 *
 * firebase.json regex rewrites forward only the original path (query string
 * stays on req.query). Direct Cloud Run requests see that same path. Patterns
 * here must stay aligned with those rewrites: one id segment, optional slash.
 */

const PREVIEW_CACHE_CONTROL = "public, max-age=300, s-maxage=3600";
const NOT_FOUND_CACHE_CONTROL = "public, max-age=60, s-maxage=300";
const SHARE_PREVIEW_MAX_INSTANCES = 5;
const BROWSER_LOOKUP_TIMEOUT_MS = 250;

// Real preview ids: company slugs (almarai, coca-cola, 7up), numeric codes
// (469, 512), and Firestore ids. Dots, tildes, and extra segments are not ids.
const PREVIEW_ID = "[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*";

/**
 * Hosting regexes, in match order. manager matches the pre-change
 * sharePreview check: portal, p, ep, ops, agency.
 * /c has an explicit numeric rule plus the slug rule (7up, coca-cola, almarai).
 */
const SHARE_PREVIEW_REWRITES = [
  { regex: "^/c/\\d+/?$", manager: false },
  { regex: `^/c/${PREVIEW_ID}/?$`, manager: false },
  { regex: `^/portal/${PREVIEW_ID}/?$`, manager: true },
  { regex: `^/client/${PREVIEW_ID}/?$`, manager: false },
  { regex: `^/promoter/${PREVIEW_ID}/?$`, manager: false },
  { regex: `^/ops/${PREVIEW_ID}/?$`, manager: true },
  { regex: `^/agency/${PREVIEW_ID}/?$`, manager: true },
  { regex: `^/p/${PREVIEW_ID}/?$`, manager: true },
  { regex: `^/ep/${PREVIEW_ID}/?$`, manager: true },
  { regex: `^/event/${PREVIEW_ID}/?$`, manager: false },
  { regex: `^/share/${PREVIEW_ID}/?$`, manager: false },
];

/**
 * Escapes HTML entities to prevent XSS in dynamic meta tags
 */
function escapeHtml(str) {
  if (!str) return "";
  return String(str)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

// In-memory TTL cache (5 minutes) to eliminate repeated Firestore round-trips on hot paths
const eventPreviewCache = new Map();
const PREVIEW_CACHE_TTL_MS = 5 * 60 * 1000;

// Equality on companySlug alone uses the automatic single-field index.
// isActive and recency are applied in memory, so this lookup does not need a
// composite index. Recency matches the client: createdAt, otherwise startDate,
// newest first (client_receipt_upload_screen, company_manager_portal_screen).
// A slug with more campaigns than the cap can miss an active one and fall
// back to the generic preview rather than advertise a closed campaign.
const SLUG_CAMPAIGN_LOOKUP_LIMIT = 100;

function timestampToMillis(value) {
  if (value == null || value === "") return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date) {
    const ms = value.getTime();
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value === "string") {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value.toDate === "function") {
    try {
      const date = value.toDate();
      if (date instanceof Date && !Number.isNaN(date.getTime())) return date.getTime();
    } catch {
      // Fall through to seconds/nanoseconds.
    }
  }
  if (typeof value === "object") {
    const seconds = value.seconds ?? value._seconds;
    if (typeof seconds === "number" && Number.isFinite(seconds)) {
      const nanos = value.nanoseconds ?? value._nanoseconds ?? 0;
      const extra = typeof nanos === "number" && Number.isFinite(nanos) ? Math.floor(nanos / 1e6) : 0;
      return seconds * 1000 + extra;
    }
  }
  return null;
}

function campaignRecencyMillis(data) {
  const created = timestampToMillis(data && data.createdAt);
  if (created != null) return created;
  const start = timestampToMillis(data && data.startDate);
  return start == null ? 0 : start;
}

function pickNewestActiveCampaign(docs) {
  const active = [];
  for (const doc of docs || []) {
    const data = doc && typeof doc.data === "function" ? doc.data() : null;
    if (!data || data.isActive !== true) continue;
    active.push(data);
  }
  if (active.length === 0) return null;
  active.sort((a, b) => campaignRecencyMillis(b) - campaignRecencyMillis(a));
  return active[0];
}

/**
 * Resolves event document from Firestore by eventId or companySlug with in-memory caching
 */
async function resolveEvent(db, eventIdParam, routeIdentifier) {
  const cacheKey = `${eventIdParam || ""}:${routeIdentifier || ""}`.toLowerCase();
  const cached = eventPreviewCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < PREVIEW_CACHE_TTL_MS) {
    return cached.data;
  }

  let result = null;
  if (eventIdParam) {
    const eventDoc = await db.collection("events").doc(eventIdParam).get();
    if (eventDoc.exists) result = eventDoc.data();
  }

  if (!result && routeIdentifier) {
    const directDoc = await db.collection("events").doc(routeIdentifier).get();
    if (directDoc.exists) {
      result = directDoc.data();
    } else {
      const cleanSlug = routeIdentifier.toLowerCase();
      const slugQuery = await db
        .collection("events")
        .where("companySlug", "==", cleanSlug)
        .limit(SLUG_CAMPAIGN_LOOKUP_LIMIT)
        .get();

      const slugDocs = slugQuery.docs || [];
      if (slugDocs.length >= SLUG_CAMPAIGN_LOOKUP_LIMIT) {
        console.warn(
          `sharePreview slug lookup for ${cleanSlug} hit the ${SLUG_CAMPAIGN_LOOKUP_LIMIT} document cap`,
        );
      }
      // No active campaign: leave result null so the generic preview is served.
      result = pickNewestActiveCampaign(slugDocs);
    }
  }

  eventPreviewCache.set(cacheKey, { data: result, timestamp: Date.now() });
  return result;
}

/**
 * Extracts and formats metadata for social share preview
 */
function extractPreviewMetadata(resolvedEvent, query, isManagerPortal) {
  let companyName = "تسهيل جيفت";
  let eventName = "منظومة إدارة العروض والهدايا الترويجية";
  let companyLogoUrl = "https://tashil-gift.web.app/icons/Icon-512.png";
  let welcomeDesc = "Tashil Gift - Smart Multi-Company Promotion & Validation Platform by Switch Point";

  if (resolvedEvent) {
    companyName = resolvedEvent.targetCompany || resolvedEvent.companyName || companyName;
    eventName = resolvedEvent.eventName || eventName;
    if (resolvedEvent.companyLogoUrl?.trim()) {
      companyLogoUrl = resolvedEvent.companyLogoUrl.trim();
    }
    const welcome = resolvedEvent.welcomeMessage?.trim() || resolvedEvent.welcomeTitle?.trim();
    if (welcome) {
      welcomeDesc = welcome;
    }
  } else if (query.companyName) {
    companyName = query.companyName;
  }

  if (query.logo) {
    companyLogoUrl = query.logo;
  }

  let pageTitle = "";
  let pageDescription = "";

  if (isManagerPortal) {
    pageTitle = `${companyName} • بوابة الشريك | Tashil Gift`;
    pageDescription = `منظومة إدارة ومتابعة الحملات الترويجية والهدايا لشركة ${companyName}`;
  } else {
    pageTitle = `${eventName} (${companyName}) | Tashil Gift`;
    pageDescription = welcomeDesc;
  }

  return {
    pageTitle,
    pageDescription,
    companyLogoUrl,
  };
}

/**
 * Builds HTML page template with rich OpenGraph / Twitter meta tags and Instant M3 Splash Loader
 */
function buildPreviewHtml({ pageTitle, pageDescription, companyLogoUrl }) {
  const escapedTitle = escapeHtml(pageTitle);
  const escapedDesc = escapeHtml(pageDescription);
  const escapedLogo = escapeHtml(companyLogoUrl);

  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapedTitle}</title>
  <meta name="description" content="${escapedDesc}">

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="preconnect" href="https://firestore.googleapis.com">

  <!-- iOS meta tags & icons -->
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="${escapedTitle}">
  <link rel="apple-touch-icon" href="/icons/Icon-192.png">

  <!-- Favicon -->
  <link rel="icon" type="image/svg+xml" href="/favicon.svg"/>
  <link rel="icon" type="image/png" href="/favicon.png"/>

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

  <link rel="manifest" href="/manifest.json">

  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      height: 100%;
      background-color: #F8FAF3;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      overflow: hidden;
    }

    #app-splash-loader {
      position: fixed;
      inset: 0;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      background-color: #F8FAF3;
      z-index: 999999;
      transition: opacity 0.28s cubic-bezier(0.4, 0, 0.2, 1), visibility 0.28s;
    }

    #app-splash-loader.loaded {
      opacity: 0;
      visibility: hidden;
      pointer-events: none;
    }

    .splash-card {
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 32px 40px;
      border-radius: 24px;
      background: #FFFFFF;
      border: 1px solid rgba(74, 93, 35, 0.14);
      box-shadow: 0 12px 32px rgba(74, 93, 35, 0.06);
      max-width: 320px;
      width: 85%;
      text-align: center;
    }

    .splash-logo-badge {
      width: 64px;
      height: 64px;
      border-radius: 18px;
      background: linear-gradient(135deg, #4A5D23 0%, #637B30 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      color: #FFFFFF;
      font-size: 28px;
      font-weight: 900;
      box-shadow: 0 6px 16px rgba(74, 93, 35, 0.25);
      margin-bottom: 16px;
      animation: pulseBadge 1.8s infinite ease-in-out;
    }

    .splash-title {
      font-size: 17px;
      font-weight: 800;
      color: #1B1C18;
      margin: 0 0 6px 0;
    }

    .splash-subtitle {
      font-size: 13px;
      color: #5C5F52;
      margin: 0 0 20px 0;
    }

    .m3-linear-progress {
      width: 100%;
      height: 6px;
      background-color: #E3E8D8;
      border-radius: 999px;
      overflow: hidden;
      position: relative;
    }

    .m3-linear-progress-bar {
      position: absolute;
      top: 0;
      bottom: 0;
      width: 45%;
      background-color: #4A5D23;
      border-radius: 999px;
      animation: m3Indeterminate 1.25s infinite cubic-bezier(0.4, 0, 0.2, 1);
    }

    @keyframes m3Indeterminate {
      0% { right: -45%; width: 35%; }
      50% { width: 55%; }
      100% { right: 100%; width: 35%; }
    }

    @keyframes pulseBadge {
      0%, 100% { transform: scale(1); }
      50% { transform: scale(1.05); }
    }
  </style>
</head>
<body>
  <div id="app-splash-loader">
    <div class="splash-card">
      <div class="splash-logo-badge">G</div>
      <h1 class="splash-title">${escapedTitle}</h1>
      <p class="splash-subtitle">جاري تهيئة البوابة الذكية...</p>
      <div class="m3-linear-progress">
        <div class="m3-linear-progress-bar"></div>
      </div>
    </div>
  </div>

  <script>
    (function() {
      var hash = window.location.hash;
      if (hash && (hash.startsWith('#/') || hash.startsWith('#!/'))) {
        var cleanPath = hash.replace(/^#[!]?/, '');
        if (cleanPath.startsWith('/')) {
          window.history.replaceState(null, '', cleanPath);
        }
      }
    })();

    function dismissSplashLoader() {
      var loader = document.getElementById('app-splash-loader');
      if (loader && !loader.classList.contains('loaded')) {
        loader.classList.add('loaded');
        setTimeout(function() { loader.remove(); }, 350);
      }
    }

    window.addEventListener('flutter-first-frame', dismissSplashLoader);
    var observer = new MutationObserver(function() {
      if (document.querySelector('flutter-view') || document.querySelector('flt-glass-pane')) {
        dismissSplashLoader();
        observer.disconnect();
      }
    });
    observer.observe(document.body, { childList: true, subtree: true });
  </script>
  <!-- Flutter Web Bootstrap -->
  <script src="/flutter_bootstrap.js" async></script>
</body>
</html>`;
}


function clearSharePreviewCache() {
  eventPreviewCache.clear();
}

function requestPath(req) {
  if (req && typeof req.path === "string" && req.path.length > 0) return req.path;
  if (req && typeof req.url === "string" && req.url.length > 0) return req.url;
  return "/";
}

/**
 * GET/HEAD on a real preview path. Returns { id, prefix, manager } or null.
 * Null means reject before any Firestore read. Query strings are ignored.
 * Percent-encoded slashes are decoded so /c/469%2Fsubadmin cannot sneak past
 * the single-segment rule. Dot segments are not normalized away.
 */
function matchSharePreviewRoute(method, rawPath) {
  const normalizedMethod = String(method || "").toUpperCase();
  if (normalizedMethod !== "GET" && normalizedMethod !== "HEAD") return null;

  const raw = String(rawPath == null ? "/" : rawPath);
  const withoutQuery = raw.split("#")[0].split("?")[0];
  if (!withoutQuery.startsWith("/")) return null;

  let pathname;
  try {
    pathname = decodeURIComponent(withoutQuery);
  } catch {
    return null;
  }

  const route = SHARE_PREVIEW_REWRITES.find((entry) => new RegExp(entry.regex).test(pathname));
  if (!route) return null;

  const segments = pathname.split("/").filter(Boolean);
  if (segments.length !== 2 || !segments[1]) return null;
  return { id: segments[1], prefix: segments[0], manager: route.manager };
}

function sendNotFound(res) {
  res.set("Cache-Control", NOT_FOUND_CACHE_CONTROL);
  res.set("Content-Type", "text/plain; charset=utf-8");
  res.status(404).send("Not Found");
}

async function handleSharePreview(req, res, db) {
  const route = matchSharePreviewRoute(req && req.method, requestPath(req));
  if (!route) {
    sendNotFound(res);
    return;
  }

  try {
    const query = (req && req.query) || {};
    const eventIdParam = query.event || "";
    const headers = (req && req.headers) || {};
    const userAgent = String(headers["user-agent"] || "").toLowerCase();
    const isSocialCrawler = /whatsapp|facebookexternalhit|facebot|twitterbot|telegrambot|linkedinbot|slackbot|discordbot|pinterest|bot|crawler|spider|preview/i.test(userAgent);

    // Same resolution order as before: ?event= doc, then path id as doc or companySlug.
    // Browsers still race Firestore against 250ms and still receive the shell.
    const cacheKey = `${eventIdParam || ""}:${route.id}`.toLowerCase();
    const cached = eventPreviewCache.get(cacheKey);
    let resolvedEvent = null;

    if (cached && Date.now() - cached.timestamp < PREVIEW_CACHE_TTL_MS) {
      resolvedEvent = cached.data;
    } else if (isSocialCrawler) {
      resolvedEvent = await resolveEvent(db, eventIdParam, route.id);
    } else {
      const timeoutMarker = Symbol("preview-timeout");
      const lookup = resolveEvent(db, eventIdParam, route.id);
      let timer;
      let raced;
      try {
        raced = await Promise.race([
          lookup.then(
            (data) => ({ data }),
            (error) => ({ error }),
          ),
          new Promise((resolve) => {
            timer = setTimeout(() => resolve(timeoutMarker), BROWSER_LOOKUP_TIMEOUT_MS);
          }),
        ]);
      } finally {
        clearTimeout(timer);
      }
      if (raced === timeoutMarker) {
        resolvedEvent = null;
      } else if (raced.error) {
        throw raced.error;
      } else {
        resolvedEvent = raced.data;
      }
    }

    const meta = extractPreviewMetadata(resolvedEvent, query, route.manager);
    res.set("Cache-Control", PREVIEW_CACHE_CONTROL);
    res.set("Content-Type", "text/html; charset=utf-8");
    res.status(200).send(buildPreviewHtml(meta));
  } catch (error) {
    console.error("Error generating share preview:", error);
    res.redirect("/index.html");
  }
}

module.exports = {
  matchSharePreviewRoute,
  handleSharePreview,
  clearSharePreviewCache,
  PREVIEW_CACHE_CONTROL,
  NOT_FOUND_CACHE_CONTROL,
  SHARE_PREVIEW_MAX_INSTANCES,
  SHARE_PREVIEW_REWRITES,
  SLUG_CAMPAIGN_LOOKUP_LIMIT,
};
