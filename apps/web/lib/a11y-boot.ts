/**
 * Runs in <head> before first paint (app/layout.tsx). Plain (not a client module) so the server
 * layout can inline it.
 *
 * 1. Applies the visitor's saved text size, contrast and reduce-motion settings to <html>, so people
 *    who rely on them never see the page flash without them. Keep the keys and attributes in step
 *    with lib/a11y-prefs.tsx and lib/motion-prefs.tsx.
 * 2. Scroll on arrival: a reload starts at the top (the browser would otherwise restore a mid-page
 *    position, which jumps around with pinned scenes, or re-follow a #section left in the address
 *    bar by a nav link). Opening a link with a #section still goes there (useHashAfterPins).
 */
export const A11Y_BOOT = `(function(){try{var h=document.documentElement,p=JSON.parse(localStorage.getItem("recall:a11y")||"{}"),s=p.textScale||1;if(s!==1)h.style.fontSize=s*100+"%";h.dataset.textScale=String(s);h.dataset.contrast=p.contrast?"high":"normal";var m=localStorage.getItem("recall:reduce-motion");if(m!==null)h.dataset.reduceMotion=String(m==="1")}catch(e){}try{history.scrollRestoration="manual";var n=performance.getEntriesByType("navigation")[0];if(n&&n.type==="reload"&&location.hash)history.replaceState(history.state,"",location.pathname+location.search)}catch(e){}})()`;
