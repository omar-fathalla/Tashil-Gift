/**
 * Session-control and status calls use their own rate-limit bucket so QR polling
 * or a broadcast can never block "restart session" (and vice versa).
 */
function wahaRateLimitScope(method, rawUrl) {
  const path = String(rawUrl || "/").split("?")[0].replace(/^\/waha(?=\/)/, "");
  const m = String(method || "GET").toUpperCase();
  if (m === "GET" && (/^\/api\/sessions(\/[^/]+)?\/?$/.test(path) ||
      /^\/api\/[^/]+\/auth\/qr\/?$/.test(path) ||
      /^\/api\/screenshot\/?$/.test(path) ||
      /^\/api\/server\/(version|status)\/?$/.test(path))) {
    return "wahaControl";
  }
  if (m === "POST" && /^\/api\/sessions\/[^/]+\/(restart|start|stop|logout)\/?$/.test(path)) {
    return "wahaControl";
  }
  return "waha";
}

module.exports = { wahaRateLimitScope };
