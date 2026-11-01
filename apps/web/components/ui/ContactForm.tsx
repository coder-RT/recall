"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { useT } from "@/i18n/I18nProvider";

type ContactError = keyof ReturnType<typeof useT>["contact"]["errors"];
type Status = "idle" | "sending" | "sent" | ContactError;

const field =
  "mt-1 block w-full min-h-11 rounded-lg border border-fb-line bg-white px-3 py-2 text-[1.02rem] text-ink focus:border-fb-blue";

/**
 * Write to Rachit without his address ever reaching the page: the form posts to /api/contact, which sends the email.
 * Sent with fetch, not a native form post, so Vercel BotID can check it (instrumentation-client.ts).
 */
export function ContactForm() {
  const t = useT();
  const [status, setStatus] = useState<Status>("idle");
  const startedAt = useRef(0);

  // when the form appeared: one sent within seconds was filled by a bot
  useEffect(() => {
    startedAt.current = Date.now();
  }, []);

  const send = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (status === "sending") return;
    const form = event.currentTarget;
    const data = new FormData(form);
    setStatus("sending");
    try {
      const res = await fetch("/api/contact", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: data.get("name"),
          email: data.get("email"),
          message: data.get("message"),
          website: data.get("website") ?? "",
          startedAt: startedAt.current,
        }),
      });
      const body = (await res.json().catch(() => ({}))) as { error?: ContactError };
      if (res.ok) {
        form.reset();
        setStatus("sent");
      } else {
        setStatus(body.error && body.error in t.contact.errors ? body.error : "failed");
      }
    } catch {
      setStatus("failed");
    }
  };

  const error = status !== "idle" && status !== "sending" && status !== "sent" ? status : null;

  return (
    <form onSubmit={send} aria-describedby="contact-privacy" className="card p-6 text-left sm:p-7">
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block font-classic text-sm font-bold text-ink">
          {t.contact.name}
          <input name="name" type="text" required maxLength={80} autoComplete="name" className={field} />
        </label>
        <label className="block font-classic text-sm font-bold text-ink">
          {t.contact.email}
          <input
            name="email"
            type="email"
            required
            maxLength={200}
            autoComplete="email"
            aria-describedby="contact-email-hint"
            className={field}
          />
          <span id="contact-email-hint" className="mt-1 block font-normal text-muted">
            {t.contact.emailHint}
          </span>
        </label>
      </div>
      <label className="mt-4 block font-classic text-sm font-bold text-ink">
        {t.contact.message}
        <textarea name="message" required minLength={10} maxLength={2000} rows={5} className={field} />
      </label>

      {/* the honeypot: off screen, out of the tab order and hidden from screen readers, so only a bot fills it */}
      <div aria-hidden="true" className="absolute -left-[9999px] h-px w-px overflow-hidden">
        <label>
          {t.contact.trap}
          <input name="website" type="text" tabIndex={-1} autoComplete="off" />
        </label>
      </div>

      <button type="submit" disabled={status === "sending"} className="btn btn-green mt-5 w-full sm:w-auto">
        {status === "sending" ? t.contact.sending : t.contact.send}
      </button>

      <div aria-live="polite" className="mt-4 min-h-6">
        <AnimatePresence mode="wait">
          {(status === "sent" || error) && (
            <motion.p
              key={status}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.2 }}
              role={error ? "alert" : undefined}
              className="rounded-lg bg-fb-blue-pale px-3 py-2 text-ink"
            >
              {error ? t.contact.errors[error] : t.contact.sent}
            </motion.p>
          )}
        </AnimatePresence>
      </div>

      <p id="contact-privacy" className="mt-3 border-t border-fb-line pt-3 font-classic text-xs text-muted">
        {t.contact.privacy}{" "}
        <a href="/privacy" className="text-fb-blue-dark underline">
          {t.contact.privacyLink}
        </a>
      </p>
    </form>
  );
}
