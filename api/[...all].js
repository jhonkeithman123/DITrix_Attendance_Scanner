import app from "../server/app.js";

export default function handler(req, res) {
    // strip the /api prefix so your Express routes keep working unchanged
  req.url = (req.url || "").replace(/^\/api/, "") || "/";
  return app(req, res);
}