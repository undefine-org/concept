/**
 * Minimal Lexical theme mapping node types to Tailwind / Notion CSS classes.
 */
export const oraTheme = {
  paragraph: "",
  heading: {
    h1: "text-4xl font-bold",
    h2: "text-2xl font-semibold",
    h3: "text-xl font-semibold",
  },
  text: {
    bold: "font-bold",
    italic: "italic",
    underline: "underline",
    strikethrough: "line-through",
    code: "font-mono bg-gray-100 px-1 rounded text-sm",
  },
  link: "text-notion-blue underline",
  quote: "border-l-4 border-gray-300 pl-4 italic",
  list: {
    ul: "list-disc pl-6",
    ol: "list-decimal pl-6",
  },
};
