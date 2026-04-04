const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");
const { onRequest } = require("firebase-functions/v2/https");

initializeApp();

const db = getFirestore();
const auth = getAuth();

const DAILY_LIMIT = Number.parseInt(process.env.DAILY_AI_REQUEST_LIMIT || "5", 10);
const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";

exports.proxyOpenAIResponses = onRequest(
  {
    region: "us-central1",
    secrets: ["OPENAI_API_KEY"],
    timeoutSeconds: 30
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }

    const idToken = extractBearerToken(req.headers.authorization);
    if (!idToken) {
      res.status(401).json({ error: "missing_auth_token" });
      return;
    }

    let decodedToken;
    try {
      decodedToken = await auth.verifyIdToken(idToken);
    } catch (error) {
      logger("verifyIdToken", error);
      res.status(401).json({ error: "invalid_auth_token" });
      return;
    }

    const usageDate = currentUTCDateKey();
    const usageRef = db.collection("aiUsage").doc(`${decodedToken.uid}_${usageDate}`);

    try {
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(usageRef);
        const currentCount = snapshot.exists ? Number(snapshot.get("count") || 0) : 0;
        if (currentCount >= DAILY_LIMIT) {
          const rateLimitError = new Error("daily_limit_reached");
          rateLimitError.code = "daily_limit_reached";
          throw rateLimitError;
        }

        transaction.set(
          usageRef,
          {
            uid: decodedToken.uid,
            dateKey: usageDate,
            count: currentCount + 1,
            updatedAt: FieldValue.serverTimestamp()
          },
          { merge: true }
        );
      });
    } catch (error) {
      if (error && error.code === "daily_limit_reached") {
        res.status(429).json({
          error: "daily_limit_reached",
          limit: DAILY_LIMIT,
          dateKey: usageDate
        });
        return;
      }

      logger("rateLimit", error);
      res.status(500).json({ error: "rate_limit_failed" });
      return;
    }

    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      res.status(500).json({ error: "missing_openai_key" });
      return;
    }

    try {
      const upstreamResponse = await fetch(OPENAI_RESPONSES_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${apiKey}`
        },
        body: JSON.stringify(req.body)
      });

      const responseText = await upstreamResponse.text();
      res.status(upstreamResponse.status);
      res.set("Content-Type", upstreamResponse.headers.get("content-type") || "application/json");
      res.send(responseText);
    } catch (error) {
      logger("forwardOpenAI", error);
      res.status(502).json({ error: "openai_proxy_failed" });
    }
  }
);

function extractBearerToken(authorizationHeader) {
  if (!authorizationHeader) {
    return null;
  }

  const match = authorizationHeader.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : null;
}

function currentUTCDateKey() {
  return new Date().toISOString().slice(0, 10);
}

function logger(stage, error) {
  console.error(`[proxyOpenAIResponses:${stage}]`, error);
}
