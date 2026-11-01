import { BrailleHero } from "@/components/scroll/BrailleHero";
import { ClockRoute } from "@/components/scroll/ClockRoute";
import { HowItWorks } from "@/components/scroll/HowItWorks";
import { MemoryFeed } from "@/components/scroll/MemoryFeed";
import { ModelCards } from "@/components/scroll/ModelCards";
import { RevealSection } from "@/components/scroll/RevealSection";
import { StoryVideo } from "@/components/scroll/story/StoryVideo";
import { Devices } from "@/components/ui/Devices";
import { Faq } from "@/components/ui/Faq";
import { getDictionary } from "@/i18n";

export default function LandingPage() {
  const t = getDictionary();
  return (
    <>
      <BrailleHero />

      <RevealSection aria-labelledby="problem-title" className="bg-white">
        <div className="mx-auto max-w-4xl px-4 py-24 text-center">
          <p data-eyebrow className="classic-label">
            {t.problem.eyebrow}
          </p>
          <h2 id="problem-title" data-heading="mask" className="mt-5 text-5xl font-extrabold text-ink sm:text-6xl">
            <span className="block overflow-hidden pb-[0.08em]">
              <span data-line className="block">
                {t.problem.line1}
              </span>
            </span>
            <span className="block overflow-hidden pb-[0.08em]">
              <span data-line className="block text-fb-blue-dark">
                {t.problem.line2}
              </span>
            </span>
          </h2>
          <ul className="mx-auto mt-10 grid max-w-3xl gap-4 text-left sm:grid-cols-3">
            {t.problem.points.map((line) => (
              <li key={line} data-reveal className="rounded-xl bg-fb-grey p-5 text-lg leading-snug text-ink">
                {line}
              </li>
            ))}
          </ul>
        </div>
      </RevealSection>

      <StoryVideo />
      <HowItWorks />
      <MemoryFeed />
      <ClockRoute />
      <ModelCards />
      <Devices />

      <RevealSection id="privacy" aria-labelledby="principles-title" className="scroll-mt-20 bg-white">
        <div className="mx-auto max-w-6xl px-4 py-24">
          <p data-eyebrow className="classic-label">
            {t.principles.eyebrow}
          </p>
          <h2 id="principles-title" data-heading="words" className="mt-4 max-w-3xl text-4xl font-extrabold text-ink sm:text-5xl">
            {t.principles.title}
          </h2>
          <ul className="mt-10 grid gap-6 sm:grid-cols-2">
            {t.principles.items.map((p) => (
              <li key={p.title} data-reveal className="rounded-2xl border border-fb-line p-6">
                <h3 className="text-xl font-extrabold text-fb-blue-dark">{p.title}</h3>
                <p className="mt-2 text-lg leading-relaxed text-ink">{p.body}</p>
              </li>
            ))}
          </ul>
          <p className="mt-8 text-lg">
            <a href="/privacy" className="font-bold text-fb-blue-dark underline">
              {t.principles.more}
            </a>
          </p>
        </div>
      </RevealSection>

      <section id="faq" aria-labelledby="faq-title" className="mx-auto max-w-3xl scroll-mt-20 px-4 py-24">
        <h2 id="faq-title" className="mb-8 text-4xl font-extrabold text-ink">
          {t.faq.title}
        </h2>
        <Faq />
      </section>
    </>
  );
}
