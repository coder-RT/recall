# Privacy in Recall

The same text is in the iPhone app (Settings → Privacy) and on the website (`/privacy`). The app also shows
**"Right now"**: what your Mac sends where under its current settings (`GET /privacy`).

## The short version

Your home's memory lives on **your own Mac**. There is no Recall account and no Recall server: nobody else holds your
scans or your memory. Some steps use **Meta's models online**, and this page says exactly what they receive.

## Kept on your devices

- **On your Mac** (the `data/` folder): every scan you upload (photos, LiDAR depth, the phone's path through the
  room), the 3D map, the things and furniture found, your own names and notes for things, and the activity log.
- **On your iPhone**: your scans until you delete them, the room map used to find your way, and the Mac's address.
  The device key is in the iPhone's Keychain.
- Between them: your home network, or an encrypted tunnel you set up yourself (Tailscale or Cloudflare Tunnel). Every
  request needs the device key.

## What leaves your Mac, to whom, and when

| What | To | When |
|---|---|---|
| Scan photos, about 50 per room (no depth, no sound) | Meta Model API: SAM 3.1 | While your Mac processes a scan, to find furniture and things |
| Your spoken question (a few seconds of audio) | Meta Model API: Muse Voice Transcribe | When you ask by voice |
| Your question as text, and what memory says about the thing (names, rooms, heights, times; no photos) | Baseten: Muse Spark Open. **Private mode:** Muse Glimmer on your Mac, so nothing leaves | Each time you ask |
| One photo from the camera | Meta Model API: SAM 3.1, and Muse Spark 1.1 only when SAM is unsure | When you check on arrival |
| The room map, things and furniture (no photos, your names or notes, or anyone's position) | Robots and agents you gave the robot key | Only while **Robot Access** is on (off by default) |
| The object name a robot asked about | Muse Spark Open (or Glimmer on your Mac), to check it is only a name | Before any robot request is answered |

These services process what they receive under their own terms. Recall doesn't claim how long they keep it.
`TODO(verify)`: link Meta's and Baseten's terms once we have the official pages.

## Never

- No account, no ads, no analytics, no tracking in the app, and nothing sold.
- No Recall server receives your home: the developer never sees your scans, your memory or your questions.
- Robots never get photos, your own names or notes for things, or anyone's position.

## Your controls

- **Delete a scan** (Scans → hold a scan → Delete): removes it from your iPhone **and your Mac**, with its photos,
  depth and the things only it found. Memory goes back to your other scans of that room.
- **Forget a thing** (Found → a thing → "Not there, forget it"): removes it from memory.
- **Robot Access** (Devices → Home robots): off by default; every robot request is in the activity log.
- **Activity log**: who did what to the memory and its sharing, kept 90 days on your Mac.
- **Private mode**: run the Guide on Muse Glimmer in LM Studio (`LLM_PROVIDER=lmstudio`), so your questions stay on
  your Mac. Scans and voice still use Meta's online models.

## This website

No cookies and no analytics. It keeps two small settings in your browser (reduce motion, and that you saw the storage
note). Vercel Speed Insights measures page speed without cookies or anything personal. "Ask by voice" sends your
recording through our server to Muse Voice Transcribe and doesn't store it. The demo shows **recorded output of a real
run**, not your data.
