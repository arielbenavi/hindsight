export type Source = "ig_reel" | "tweet" | "web" | "note";
export type Status = "pending" | "done" | "failed";

export type Item = {
  id: number;
  source: Source;
  source_url: string | null;
  kind: string | null;
  raw_text: string | null;
  summary: string | null;
  on_screen_text: string | null;
  transcript: string | null;
  category: string | null;
  key_takeaways: string[] | null;
  saved_at: string;
  status: Status;
};

export const CATEGORIES = [
  "coding",
  "quant",
  "music",
  "life-hack",
  "productivity",
  "other",
] as const;

export const SOURCES: Source[] = ["ig_reel", "tweet", "web", "note"];
