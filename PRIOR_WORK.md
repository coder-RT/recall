# Prior work

None.

- The repo was started fresh on Oct 26, 2026, the day the Meta Global AI Developer Hackathon began, and everything in it
  is event work. The commit history shows when each part was built.
- No code written before the hackathon, and no code from any other project, was copied in.
- Every model the product calls at runtime is a Meta model, as the hackathon rules require: Muse Spark Open, Muse Glimmer,
  Muse Spark, Muse Spark 1.1, SAM 3.1, MapAnything, Muse Voice Transcribe and Llama Prompt Guard. None of them is our
  work and none was fine-tuned by us; they are called as hosted Meta services or run from their published weights.
- The open-source libraries the code builds on (Next.js, React, three.js, FastAPI, NumPy, Open3D and the rest) are ordinary
  dependencies installed from their package registries, never copied into the repo. `THIRD_PARTY.md` lists each library,
  service and model with its licence.
