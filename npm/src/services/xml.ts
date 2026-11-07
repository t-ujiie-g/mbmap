// DOM helpers for capabilities documents: elements are matched by local name, so the readers take
// any namespace prefix (or none) as the services write them.

const XLINK = "http://www.w3.org/1999/xlink";

/** The longest document `parseXml` reads, in UTF-16 code units. */
export const MAX_XML_LENGTH = 32 * 1024 * 1024;

/** `xml` parsed by the host's DOMParser; a malformed document or a service exception throws. */
export function parseXml(xml: string | Document, what: string): Element {
  if (typeof xml === "string" && xml.length > MAX_XML_LENGTH) throw new Error(`mbmap: services: ${what} is too long`);
  const doc = typeof xml === "string" ? new DOMParser().parseFromString(xml, "application/xml") : xml;
  const root = doc.documentElement;
  if (!root || root.localName === "parsererror" || doc.getElementsByTagName("parsererror").length) {
    throw new Error(`mbmap: services: ${what} is not well-formed XML`);
  }
  if (/ExceptionReport$/.test(root.localName)) {
    const message = text(first(root, "ServiceException") ?? first(first(root, "Exception"), "ExceptionText")) || text(root);
    throw new Error(`mbmap: services: ${what}: ${message}`);
  }
  return root;
}

/** The child elements of `e` named `name` (any, without a name). */
export function children(e: Element | null | undefined, name?: string): Element[] {
  const out: Element[] = [];
  for (let n = e?.firstChild; n; n = n.nextSibling) {
    if (n.nodeType === 1 && (name === undefined || (n as Element).localName === name)) out.push(n as Element);
  }
  return out;
}

/** The first child element of `e` named `name`. */
export function first(e: Element | null | undefined, name: string): Element | null {
  return children(e, name)[0] ?? null;
}

/** The element reached from `e` through the first child of each name. */
export function at(e: Element | null | undefined, ...names: string[]): Element | null {
  let out = e ?? null;
  for (const name of names) out = first(out, name);
  return out;
}

/** The trimmed text of `e`, "" when there is none. */
export function text(e: Element | null | undefined): string {
  return (e?.textContent ?? "").trim();
}

/** The trimmed text of each child of `e` named `name`. */
export function texts(e: Element | null | undefined, name: string): string[] {
  return children(e, name).map(text);
}

/** The text of the child `name`, or undefined when it is missing or empty. */
export function optional(e: Element | null | undefined, name: string): string | undefined {
  return text(first(e, name)) || undefined;
}

/** `e`'s xlink:href. */
export function href(e: Element | null | undefined): string | undefined {
  return e?.getAttributeNS(XLINK, "href") || e?.getAttribute("xlink:href") || undefined;
}

/** The numbers of a space-separated list, as in an OWS corner. */
export function numbers(s: string): number[] {
  return s.split(/\s+/).filter(Boolean).map(Number);
}

/** The `minx`, `miny`, `maxx`, `maxy` attributes of a WMS or WFS 1.0 box. */
export const attributeBox = (e: Element): number[] => ["minx", "miny", "maxx", "maxy"].map((n) => Number(e.getAttribute(n)));

/** An OWS box's LowerCorner then UpperCorner. */
export const corners = (e: Element): number[] => [...numbers(text(first(e, "LowerCorner"))), ...numbers(text(first(e, "UpperCorner")))];
