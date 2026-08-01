"""Public legal pages (privacy policy).

Apple requires a publicly reachable Privacy Policy URL for any app that uses
HealthKit. Serving it from the backend means the URL lives next to the service
that actually processes the data (``https://<host>/privacy``), so there's one
less thing to host separately. It's a static page — no auth, no DB.

Edit ``EFFECTIVE_DATE`` / ``CONTACT_EMAIL`` and the copy below when the data
practices change, then redeploy.
"""

from __future__ import annotations

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["legal"])

EFFECTIVE_DATE = "August 1, 2026"
CONTACT_EMAIL = "aditivk94@gmail.com"

_PRIVACY_HTML = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>enhale — Privacy Policy</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{
    font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    max-width: 720px; margin: 0 auto; padding: 32px 20px 64px; color: #1c1c1e;
  }}
  @media (prefers-color-scheme: dark) {{ body {{ background: #000; color: #e5e5e7; }} }}
  h1 {{ font-size: 1.7rem; margin-bottom: 4px; }}
  h2 {{ font-size: 1.2rem; margin-top: 2rem; }}
  .updated {{ color: #8e8e93; font-size: 0.9rem; margin-top: 0; }}
  ul {{ padding-left: 1.2rem; }}
  a {{ color: #0a84ff; }}
  code {{ background: rgba(127,127,127,0.15); padding: 1px 5px; border-radius: 4px; }}
</style>
</head>
<body>
<h1>enhale Privacy Policy</h1>
<p class="updated">Last updated: {EFFECTIVE_DATE}</p>

<p>enhale ("we", "the app") helps you log meals by voice or text and correlate
your nutrition with your health data. This policy explains what we collect, how
we use it, and the choices you have. We built enhale to work for you — we do not
sell your data and we do not use your health data for advertising.</p>

<h2>Information we collect</h2>
<ul>
  <li><strong>Account information</strong> — the email address and password you
      use to sign in. Passwords are stored only as a salted cryptographic hash;
      we never store or see your plaintext password.</li>
  <li><strong>Meals you log</strong> — the text you type or the transcription of
      what you say, along with the structured nutrition data derived from it.</li>
  <li><strong>Apple Health data</strong> — when you grant permission, the app
      reads workouts, sleep, daily activity (steps, energy), and vitals (resting
      heart rate, heart-rate variability, body mass) from Apple Health and syncs
      a summary to your account so it can be correlated with your meals.</li>
  <li><strong>Lab reports you upload</strong> — blood-work files (PDF, PNG, JPEG)
      you choose to add, and the biomarker values extracted from them.</li>
  <li><strong>Profile &amp; symptom context</strong> — optional information you
      provide, such as age, medications, supplements, family history, and
      symptoms, used to personalize your insights.</li>
</ul>

<h2>How we use your information</h2>
<p>Your information is used <strong>only to provide the app's functionality</strong>:
to log and analyze your meals, to sync and summarize your health data, to
generate personalized insights and root-cause "investigations", and to keep you
signed in. We do <strong>not</strong> use it for advertising, and we do
<strong>not</strong> sell or rent it to anyone.</p>

<h2>How your data is processed and shared</h2>
<ul>
  <li><strong>Your enhale account backend</strong> stores your data so it is
      available across your sessions. It is hosted on our infrastructure provider
      and associated with your account.</li>
  <li><strong>AI processing (Anthropic).</strong> To turn your meal descriptions
      into structured nutrition data, to read your uploaded lab reports, and to
      generate insights, the relevant text and images are sent to Anthropic's
      Claude API, which processes them on our behalf as a service provider. This
      data is not used to train their models.</li>
  <li>We do not share your data with any other third parties except as required
      by law.</li>
</ul>

<h2>Apple Health (HealthKit)</h2>
<p>enhale accesses Apple Health data only with your explicit permission, which
you can grant or revoke at any time in the iOS <em>Settings &rarr; Privacy &amp;
Security &rarr; Health</em> screen. Health data obtained through HealthKit is
used solely to provide enhale's nutrition and health insights. We never use
HealthKit data for advertising or marketing, and we never sell it or share it
with data brokers.</p>

<h2>Data retention and deletion</h2>
<p>We keep your data for as long as your account exists. You can request deletion
of your account and all associated data at any time by emailing
<a href="mailto:{CONTACT_EMAIL}">{CONTACT_EMAIL}</a>, and we will delete it.</p>

<h2>Security</h2>
<p>Passwords are hashed with a modern algorithm (argon2). Sessions use
short-lived tokens, and traffic between the app and the backend is encrypted over
HTTPS. No system is perfectly secure, but we take reasonable measures to protect
your information.</p>

<h2>Children</h2>
<p>enhale is not directed to children under 13, and we do not knowingly collect
information from them.</p>

<h2>Changes to this policy</h2>
<p>We may update this policy as the app evolves. Material changes will be
reflected here with a new "Last updated" date.</p>

<h2>Contact</h2>
<p>Questions or requests? Email
<a href="mailto:{CONTACT_EMAIL}">{CONTACT_EMAIL}</a>.</p>
</body>
</html>"""


@router.get("/privacy", response_class=HTMLResponse)
async def privacy_policy() -> HTMLResponse:
    """Public HTML privacy policy (Apple requires this URL for HealthKit apps)."""
    return HTMLResponse(content=_PRIVACY_HTML)
