// tlachart view for LeadClaimChart: the reader's words, coarse enough to read.
// Detail steps inside "claiming" collapse: a step that stays in one label is
// not drawn, so the chart shows the hand-offs, the claim, and the decision.
const coarse = (s) =>
  s === "try"
    ? "wants a place"
    : s === "holding"
      ? "HOLDS a place"
      : s === "done" || s === "refused" || s === "failed"
        ? "finished"
        : "claiming";

const place = (v) => {
  const held = (v.holds || []).join(", ");
  return held ? `place: ${held}` : "place: none";
};

export const state = (v) => `a1 ${coarse(v.stage.a1)} | a2 ${coarse(v.stage.a2)} | ${place(v)}`;

export const step = (action) =>
  ({
    LeadClaimStart: "takes the leads lock",
    LeadSameIdRefuse: "same id live, exit 2",
    LeadPublish: "rm stale dir, mkdir",
    LeadWritePid: "writes start and pid",
    LeadPublishFail: "dir lost, exit 4",
    LeadCountOthers: "counts live others, reclaims dead",
    LeadVerifyOwn: "own pid still there",
    LeadVerifyFail: "pid lost, exit 4",
    LeadUnlock: "releases the leads lock",
    LeadAccept: "accepts the place",
    LeadRefuse: "cap reached, exit 4",
    LeadRelease: "cleanup releases the place",
  })[action] ?? null;

export const title = "Lead claim: publish under one lock, then count live others";
