import type { ModelKind } from "@/components/scroll/ModelGlyph";
import type { MemoryPost } from "@/content/posts";

/**
 * Every piece of text on the site, in English. Other languages copy this file and are typed as
 * `Dictionary`, so nothing can be left out. `{name}` placeholders are filled by `format()`.
 * Sample content (posts, answers, the story, the route) is illustrative, not real output.
 */
export const en = {
  meta: {
    title: "Recall: find your things by voice",
    description:
      "Voice-first 3D memory of your home for blind and low-vision people. Walk through once, then ask “where are my keys?” and hear step-by-step directions.",
  },

  nav: {
    skip: "Skip to content",
    home: "Recall, back to top",
    sections: "Sections",
    tryDemo: "Try the demo",
    links: [
      { href: "#how", label: "How it works" },
      { href: "#feed", label: "Memories" },
      { href: "#directions", label: "Directions" },
      { href: "#models", label: "Models" },
      { href: "#faq", label: "FAQ" },
    ],
  },

  braille: {
    label: "{word} in Braille",
    capsSign: ", with the capital-word sign",
  },

  hero: {
    tagline: "Recall remembers where you put things, and walks you back to them.",
    brailleCaption: "RECALL in Braille",
    capitalsNote: "(the first two cells mean all capitals)",
    intro: "For blind and low-vision people. Walk through your home once with an iPhone, then ask “where are my keys?” and hear the way there.",
    seeHow: "See how it works",
    browse: "Browse sample memories",
    // the connected-home band under the hero copy (decorative)
    rooms: ["Living room", "Kitchen", "Bedroom"],
    justNow: "just now",
  },

  ask: {
    title: "Ask Recall",
    subtitle: "It’s free, and it’s all spoken out loud.",
    pick: "Pick a question:",
    // landmark first, then shelf and height, then time: the spoken style Recall is designed for
    questions: [
      { q: "Where are my keys?", a: "On the hallway shelf, second level, chest height. Seen 12 minutes ago.", words: "keys|key" },
      { q: "Where did I leave my glasses?", a: "On the sofa armrest, right side, knee height. Seen 2 hours ago.", words: "glasses|specs|spectacles" },
      { q: "Where is my wallet?", a: "On the bedside table, waist height. Seen yesterday at 18:40, so it may have moved.", words: "wallet|purse" },
      { q: "Where is my passport?", a: "I haven’t seen your passport yet. Try walking through the study and I’ll remember it.", words: "passport" },
    ],
    noMatch: "This demo knows four things: your keys, glasses, wallet and passport. Try asking about one of them.",
    voice: "Ask by voice",
    listening: "Listening… tap to send",
    working: "Working it out…",
    voiceNote: "Your voice goes to Meta’s Muse Voice to become text. Recall doesn’t keep it.",
    youAsked: "You asked:",
    says: "Recall says",
    hear: "Hear it",
    disclaimer: "Illustrative example, not real output. Answers come from the 3D map, never from guesses.",
    errors: {
      microphone: "The microphone isn’t available. Check this site’s microphone permission.",
      not_configured: "Voice questions aren’t set up on this server yet.",
      wrong_format: "That recording couldn’t be sent. Try again.",
      rate_limited: "Too many questions at once. Try again in a minute.",
      too_long: "That recording is too long.",
      too_short: "I didn’t hear anything. Try again.",
      unreachable: "Couldn’t reach the speech service.",
      failed: "Couldn’t understand that recording.",
      empty: "I didn’t catch that. Try again.",
    },
  },

  problem: {
    eyebrow: "The everyday problem",
    line1: "“Where did I",
    line2: "put my keys?”",
    points: [
      "Searching by touch takes time, and moved things are easy to miss.",
      "Asking someone else every time costs a little independence.",
      "Labels and apps that read photos don’t know where the photo was taken.",
    ],
  },

  story: {
    eyebrow: "A sample story",
    title: "One morning, one mug.",
    postLabel: "Video post: One morning, one mug",
    author: "Recall",
    meta: "Sample story · illustrative · 0:12",
    sceneLabel:
      "Animation: Sam looks for his mug on the sofa and the shelf, asks Recall, follows the route to the kitchen table and finds the mug, which smiles and waves.",
    captions: {
      wants: "Sam wants his favourite mug.",
      notHere: "Not on the sofa. Not on the shelf.",
      asks: "“Hey Recall, where’s my mug?”",
      answer: "“Kitchen table, right of the plant, waist height.”",
      here: "“Over here, by the plant!”",
      there: "“There you are!”",
      found: "“You found me!”",
    },
    transcriptLabel: "Transcript:",
    transcript:
      "Sam wants his favourite mug. He checks the sofa, then the shelf: not there. He asks Recall where his mug is. Recall answers: kitchen table, right of the plant, waist height, and a route appears from where he stands. He walks there. “Over here, by the plant!” calls the mug. “There you are!” says Sam. “You found me!”",
    listen: "Listen to the story",
    pause: "Pause the story",
    replay: "Replay",
    position: "Story position",
    positionValue: "{current} of {total}",
    play: "Play the story",
    soundOn: "Turn on narration",
    soundOff: "Turn off narration",
    shares: "Sample · 32 shares",
    like: "Like",
    share: "Share",
  },

  how: {
    eyebrow: "How it works",
    title: "Three steps. No screen needed.",
    stepOf: "Step {n} of {total}",
    steps: [
      {
        title: "Walk through once",
        body: "Hold your iPhone and walk through your home. Recall records the rooms, the furniture and where your things are, in 3D, with real distances.",
        meta: "LiDAR + camera · about 5 minutes",
      },
      {
        title: "Ask out loud",
        body: "“Where are my keys?” Recall finds the last place it saw them and describes it the way you would: landmark first, then shelf and height.",
        meta: "Voice in, voice out",
      },
      {
        title: "Hear the way there",
        body: "Step-by-step directions from where you stand, as clock-face turns and steps, with an optional tap pattern on your Apple Watch.",
        meta: "Live guidance · haptics",
      },
    ],
  },

  feed: {
    eyebrow: "Sample memories · illustrative",
    title: "Your things, posting where they are.",
    intro:
      "Every object Recall sees gets a memory: the room, the landmark, the shelf, the height and when it was last seen. On your phone it’s spoken; here it’s drawn as a feed.",
    keepScrolling: "Keep scrolling",
    postLabel: "{object}, last seen {seen}",
    seenBy: "Seen by Recall",
    stats: "{asks} asks · {sightings} sightings",
    reactionsLabel: "Reactions",
    guideMe: "Guide me",
    share: "Share",
    reactions: [
      { id: "like", emoji: "👍", label: "Like" },
      { id: "love", emoji: "❤️", label: "Love" },
      { id: "haha", emoji: "😆", label: "Haha" },
      { id: "wow", emoji: "😮", label: "Wow" },
      { id: "sad", emoji: "😢", label: "Sad" },
      { id: "angry", emoji: "😡", label: "Angry" },
    ],
    posts: [
      {
        id: "keys",
        object: "Keys",
        emoji: "🔑",
        seen: "12 min ago",
        room: "Hallway",
        text: "On the hallway shelf, second level, about chest height. Left of the blue bowl.",
        tags: ["Hallway", "Shelf", "ChestHeight"],
        tiles: ["hallway", "shelf", "door", "desk", "kitchen"],
        more: 1,
        reactions: 24,
        asks: 7,
      },
      {
        id: "glasses",
        object: "Reading glasses",
        emoji: "👓",
        seen: "2 h ago",
        room: "Living room",
        text: "On the sofa armrest, right side, about knee height. Last seen next to the remote.",
        tags: ["LivingRoom", "Sofa", "KneeHeight"],
        tiles: ["sofa", "bedside", "desk", "shelf", "hallway"],
        more: 2,
        reactions: 41,
        asks: 12,
      },
      {
        id: "wallet",
        object: "Wallet",
        emoji: "👛",
        seen: "Yesterday, 18:40",
        room: "Bedroom",
        text: "On the bedside table, top surface, waist height. Seen more than a day ago, so it may have moved.",
        tags: ["Bedroom", "Bedside", "WaistHeight"],
        tiles: ["bedside", "door", "sofa", "kitchen", "shelf"],
        more: 1,
        reactions: 18,
        asks: 4,
      },
      {
        id: "phone",
        object: "Phone",
        emoji: "📱",
        seen: "35 min ago",
        room: "Kitchen",
        text: "On the kitchen counter, right of the kettle, about waist height. Face down, near the edge.",
        tags: ["Kitchen", "Counter", "WaistHeight"],
        tiles: ["kitchen", "desk", "hallway", "shelf", "sofa"],
        more: 3,
        reactions: 33,
        asks: 9,
      },
      {
        id: "remote",
        object: "TV remote",
        emoji: "📺",
        seen: "1 h ago",
        room: "Living room",
        text: "Between the sofa cushions, middle seat, about knee height.",
        tags: ["LivingRoom", "Sofa", "KneeHeight"],
        tiles: ["sofa", "shelf", "bedside", "door", "desk"],
        more: 2,
        reactions: 27,
        asks: 15,
      },
      {
        id: "mug",
        object: "Favourite mug",
        emoji: "☕",
        seen: "This morning, 08:15",
        room: "Study",
        text: "On the desk, left of the keyboard, about waist height. Handle pointing towards the window.",
        tags: ["Study", "Desk", "WaistHeight"],
        tiles: ["desk", "kitchen", "shelf", "hallway", "door"],
        more: 1,
        reactions: 12,
        asks: 3,
      },
    ] as MemoryPost[],
  },

  directions: {
    eyebrow: "Directions",
    title: "Spoken like a clock face.",
    intro: "Turns are clock positions from where you face, distances are steps. A tap pattern on your wrist can confirm each turn.",
    note: "Illustrative route, not a real home.",
    // `clock` is the hour the hand points to for that step
    steps: [
      { clock: 2, text: "Turn to 2 o’clock.", detail: "You are facing the kitchen door." },
      { clock: 2, text: "Walk 4 steps.", detail: "The hallway opens on your left." },
      { clock: 10, text: "Turn to 10 o’clock.", detail: "The shelf is straight ahead." },
      { clock: 12, text: "Walk 2 steps. Reach up to chest height.", detail: "Your keys are on the second shelf." },
    ],
  },

  models: {
    eyebrow: "Built on Meta’s models",
    title: "Open models for seeing, mapping, listening and talking.",
    status: "Status: planned. These are being wired up during the event; nothing on this page is their output yet.",
    planned: "planned",
    items: [
      { name: "SAM 3.1", kind: "see" as ModelKind, role: "Finds and outlines everyday objects in every frame of the walkthrough.", path: "services/pipeline/segment.py" },
      { name: "MapAnything", kind: "map" as ModelKind, role: "Turns the walkthrough into a metric 3D map with camera poses and depth.", path: "services/pipeline/reconstruct.py" },
      { name: "Muse Spark Open", kind: "talk" as ModelKind, role: "The agent that calls tools and phrases the answer (Muse Glimmer as the open-weights alternative). Geometry decides the facts.", path: "services/api/agent/" },
      { name: "Muse Voice Transcribe", kind: "listen" as ModelKind, role: "Turns your spoken question into text.", path: "services/api/voice/" },
    ],
    glyph: {
      label: "mug",
      answer: "Second shelf, chest height.",
      question: "“where are my keys?”",
    },
  },

  principles: {
    eyebrow: "Accessibility & privacy",
    title: "Built to be trusted without looking.",
    items: [
      { title: "VoiceOver first", body: "Every screen works without sight. Every control has a spoken label. Nothing depends on colour alone." },
      { title: "Geometry decides", body: "Places, distances and times come from the 3D map. The language model only phrases them, so it cannot invent a location." },
      { title: "Your home stays yours", body: "Raw walkthrough video is never stored. Only the map and the objects found in it are kept." },
      { title: "Honest when unsure", body: "If something has not been seen, or was seen long ago, Recall says so and suggests which room to walk through." },
    ],
  },

  faq: {
    title: "Questions",
    items: [
      {
        q: "Who is Recall for?",
        a: "Blind and low-vision people who want to find everyday things at home on their own, without asking someone or searching by touch.",
      },
      { q: "Do I need special hardware?", a: "An iPhone with LiDAR for the walkthrough. An Apple Watch is optional, for tap-pattern directions." },
      {
        q: "What happens when I move something?",
        a: "Recall only knows what it last saw. Walk through the room again and it updates. If a sighting is old, Recall tells you how old.",
      },
      { q: "Is this a medical device?", a: "No. Recall is an independence and accessibility tool. It does not give health or vision-care advice." },
      {
        q: "Is the feed on this page real?",
        a: "No. The memories and answers shown here are illustrative examples of the kind of answer Recall is designed to give.",
      },
    ],
  },

  footer: {
    copyright: "{name} © 2026 · Apache-2.0",
    source: "Source code",
    linkedin: "LinkedIn",
    github: "GitHub",
    fineprint: "Built by {author} during the {event}. Not affiliated with or endorsed by Meta.",
  },

  cookie: {
    region: "Privacy notice",
    bar: "Recall · Privacy",
    title: "No tracking cookies here.",
    body: "This site has no analytics or ads. It only saves two small settings on this device: your Reduce motion choice, and that you’ve seen this note.",
    privacy: "Privacy",
    gotIt: "Got it",
  },

  a11y: {
    button: "Accessibility",
    title: "Accessibility",
    saved: "Saved in this browser. Shortcut: Alt+A.",
    textSize: "Text size",
    magnifier: { label: "Magnifier", hint: "Text you point at or tab to appears very large at the bottom." },
    lens: { label: "Magnifying glass", hint: "A round 2× lens follows your mouse." },
    readAloud: { label: "Read aloud", hint: "Speaks what you focus or click. Not needed with a screen reader.", unavailable: "This browser can’t speak text." },
    contrast: { label: "High contrast", hint: "Black, white and yellow." },
    motion: { label: "Reduce motion", hint: "Stops animations and scroll effects." },
    readSection: "Read this section",
    stop: "Stop reading",
    voiceTip: "You can also ask the demo a question out loud: “Ask by voice” in the Ask Recall card.",
  },

  app: {
    homes: { title: "Your homes", body: "Coming during the event: scanned homes appear here." },
    home: { title: "Home {id}", fallback: "Home", body: "Coming during the event: objects and when they were last seen." },
    viewer: {
      title: "3D viewer",
      idSuffix: " · {id}",
      body: "New during the event: the point cloud, the room model and a pin on everything Recall found. A demo aid, not the product.",
      empty: "No scan for this home yet. Try the sample room: /homes/demo-flat/viewer.",
      sample: {
        alt: "A 3D scan of one room in our flat, with what Recall found in it.",
        label:
          "A real run of our pipeline: an iPhone walk-through with its own motion and depth data, rebuilt on the Mac, then searched for furniture and everyday things.",
        scale: "Sizes are in metres, from the phone’s LiDAR.",
        hint: "Drag sideways to turn the room.",
        loading: "Loading the scan…",
        posterAlt: "A still picture of the scanned room with pins on the things Recall found.",
        colour: "Colour",
        modes: { height: "Height", photo: "Photo", confidence: "Confidence" },
        layers: "Layers",
        grid: "Floor grid",
        bands: "Height bands",
        surfaces: "Flat surfaces",
        room: "Walls and furniture",
        things: "Things",
        found: {
          title: "What Recall found",
          body: "Each one is a pin in the room. Choose one to highlight it. Colours are measured from the photos.",
          row: "{thing}, {band} height ({z} m)",
          sure: "{pct}% sure",
          furniture: "Furniture: {n} pieces ({kinds}).",
        },
        bandsTitle: "Height bands",
        bandsBody: "How Recall describes where something is: by the band its position falls in.",
        bandNames: { floor: "Floor", knee: "Knee", waist: "Waist", chest: "Chest", head: "Head" },
        bandRange: "{from} to {to} m",
        bandBelow: "under {to} m",
        bandAbove: "over {from} m",
        surfacesTitle: "Flat surfaces found",
        surfacesBody:
          "Found from the geometry alone: level patches where points pile up, such as desk tops, seats and shelf levels.",
        surfaceRow: "{w} × {d} m at {z} m ({band})",
        stats: {
          label: "From this run",
          frames: "Frames from the phone",
          rebuild: "Seconds on the Mac",
          sam: "SAM 3.1 calls",
          points: "Points shown",
        },
      },
    },
  },
};
