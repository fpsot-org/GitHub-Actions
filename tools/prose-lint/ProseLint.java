// SPDX-License-Identifier: Apache-2.0
//
// Adapted from the prose checker of the writing-style skill proposed for the Quarkus project
// (Apache-2.0). Changes: AsciiDoc input and a French mode.

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Lint a Markdown or AsciiDoc draft for readability.
 * <p>
 * The checks cover the mechanical part of the writing-style skill: sentence and paragraph length, passive
 * voice, nominalizations, vague words, parentheses, dashes and semicolons that join clauses, and noun
 * clusters. Code blocks, inline code, URLs, headings, tables and {@code Fixes #n} lines are skipped.
 * <p>
 * AsciiDoc files ({@code .adoc}) skip delimited blocks (listings, literals, passthroughs, comments, tables, quotes,
 * examples, sidebars), attribute and block-attribute lines, headings, block titles, comments,
 * {@code include::} and {@code image::} lines, and keep only the text of links and cross-references.
 * <p>
 * With {@code --lang fr}, only the length checks run: the word lists behind the other checks are English.
 * <p>
 * Usage: {@code java ProseLint.java [--lang en|fr] [--max-words N] FILE...}.
 * The exit code is 1 when a finding is reported and 2 on a usage error.
 */
public class ProseLint {

    private static final int MAX_SENTENCES = 6;

    private static final Pattern FENCE = Pattern.compile("^\\s*```");
    private static final Pattern SKIP_LINE = Pattern.compile(
            "^(#|\\||<img)|^-?\\s*(Fixes|Closes|Resolves|Part of|Related to|Release note)\\b", Pattern.CASE_INSENSITIVE);
    private static final Pattern LIST_ITEM = Pattern.compile("^(\\s*[-*+]|\\s*\\d+\\.)\\s+");
    private static final Pattern INLINE_CODE = Pattern.compile("`[^`]*`");
    private static final Pattern LINK = Pattern.compile("\\[([^\\]]*)\\]\\([^)]*\\)");
    private static final Pattern URL = Pattern.compile("https?://\\S+");
    private static final Pattern VERSION = Pattern.compile("\\b\\d+\\.\\d+(\\.\\d+)?\\b");
    private static final Pattern ABBREV = Pattern.compile("\\b(e\\.g|i\\.e|vs|etc|cf)\\.");
    private static final Pattern SENTENCE_END = Pattern.compile("(?<=[.!?])(?:\\*\\*)?\\s+(?=[\\p{Lu}0-9#\"'(\\[*«]|CODE|URL)");
    private static final Pattern WORD = Pattern.compile("[\\p{L}\\p{M}0-9_'’-]+");
    private static final Pattern TOKEN = Pattern.compile("[\\p{L}-]+");
    private static final Set<String> ADOC_DELIMITERS = Set.of("----", "....", "++++", "////", "|===", "====", "****", "____");
    private static final Pattern ADOC_SKIP_LINE = Pattern.compile("^(:|\\[|=|//|\\.\\p{L}|include::|image::|ifdef::|ifndef::|endif::)");
    private static final Pattern ADOC_MACRO = Pattern.compile("\\b(?:xref|link|mailto):[^\\[\\s]*\\[([^\\]]*)\\]");
    private static final Pattern ADOC_URL_TEXT = Pattern.compile("https?://[^\\[\\s]+\\[([^\\]]*)\\]");
    private static final Pattern ADOC_XREF = Pattern.compile("<<[^,>]+,\\s*([^>]+)>>");
    private static final Pattern ADOC_BARE_XREF = Pattern.compile("<<([^>]+)>>");

    private static final Pattern NOUNISH = Pattern.compile("^[a-z][a-z-]+$");

    private static final String IRREGULAR = "made|done|seen|taken|given|written|built|set|kept|held|run|sent|"
            + "put|read|found|left|lost|met|paid|said|told|thought|brought|bought|caught|chosen|driven|known|"
            + "shown|thrown|drawn|grown|begun|broken|spoken|forgotten|hidden|bound|sought|fed|led|dealt";
    private static final Pattern PASSIVE = Pattern.compile(
            "\\b(?:is|are|was|were|be|been|being|gets?|got)\\s+(?:\\w+ly\\s+)?(?:\\w+ed|" + IRREGULAR + ")\\b(?:\\s+by\\b)?",
            Pattern.CASE_INSENSITIVE);
    private static final Set<String> STATE_WORDS = Set.of("closed", "open", "unused", "related", "unrelated",
            "needed", "required", "set", "unset", "limited", "supposed", "interested", "tired", "done", "left",
            "expected", "allowed", "based", "named", "called", "deprecated", "documented", "resolved", "merged",
            "enabled", "disabled", "configured");

    private static final Pattern NOMINAL = Pattern.compile("\\b(\\w{5,}(?:tion|sion|ment|ance|ence))\\s+of\\b",
            Pattern.CASE_INSENSITIVE);
    private static final Set<String> NOMINAL_OK = Set.of("extension", "extensions", "statement", "environment",
            "exception", "option", "section", "function", "application", "version", "condition", "position",
            "documentation", "configuration", "permission", "session", "connection", "argument", "element",
            "fragment", "instance", "reference", "description", "collection", "annotation", "transaction",
            "definition", "assertion");

    private static final Pattern VAGUE = Pattern.compile("\\b(it should be noted|in order to|the fact that|"
            + "a number of|note that|of course|as well as|appropriately|appropriate|facilitates|facilitate|"
            + "currently|basically|obviously|leverages|leverage|performs|perform|utilizes|utilize|ensures|"
            + "ensure|somewhat|clearly|various|really|fairly|simply|quite|very|just|etc)\\b\\.?",
            Pattern.CASE_INSENSITIVE);

    private static final Set<String> STOP = Set.of(("a an the and or but if then than so of in on at to for from "
            + "by with without into onto over under as is are was were be been being it its this that these those "
            + "there here not no nor which who whom whose what when where why how all any each every some such only "
            + "also still yet already again now once more most less least very too can could may might will would "
            + "shall should must do does did done has have had having one two three four five first second last next "
            + "new old same other another own after before while until because since though although unless whether "
            + "about above below between through during within among via per both either neither").split(" "));

    record Paragraph(int line, String text) {
    }

    record Finding(int line, String message) {
    }

    public static void main(String[] args) throws IOException {
        int maxWords = 20;
        String lang = "en";
        List<Path> files = new ArrayList<>();
        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("--max-words") && i + 1 < args.length) {
                maxWords = Integer.parseInt(args[++i]);
            } else if (args[i].equals("--lang") && i + 1 < args.length) {
                lang = args[++i];
                if (!lang.equals("en") && !lang.equals("fr")) {
                    System.err.println("unsupported language: " + lang + " (use en or fr)");
                    System.exit(2);
                }
            } else {
                files.add(Path.of(args[i]));
            }
        }
        if (files.isEmpty()) {
            System.err.println("usage: ProseLint.java [--lang en|fr] [--max-words N] FILE...");
            System.exit(2);
        }
        int total = 0;
        for (Path file : files) {
            String text = Files.readString(file, StandardCharsets.UTF_8).replace("\r", "");
            if (text.startsWith("\uFEFF")) {
                text = text.substring(1);
            }
            boolean asciidoc = file.toString().endsWith(".adoc");
            List<Finding> findings = lint(text, maxWords, asciidoc, lang.equals("en"));
            total += findings.size();
            System.out.println("== " + file + ": " + findings.size() + " finding(s)");
            for (Finding f : findings) {
                System.out.println("  L" + f.line() + ": " + f.message());
            }
        }
        System.exit(total == 0 ? 0 : 1);
    }

    static List<Finding> lint(String text, int maxWords) {
        return lint(text, maxWords, false, true);
    }

    static List<Finding> lint(String text, int maxWords, boolean asciidoc, boolean english) {
        List<Finding> findings = new ArrayList<>();
        for (Paragraph p : asciidoc ? asciidocParagraphs(text) : paragraphs(text)) {
            List<String> sentences = sentences(p.text());
            if (sentences.size() > MAX_SENTENCES) {
                findings.add(new Finding(p.line(),
                        "paragraph has " + sentences.size() + " sentences (max " + MAX_SENTENCES + ")"));
            }
            for (String s : sentences) {
                int words = count(WORD, s);
                if (words > maxWords) {
                    findings.add(new Finding(p.line(), words + " words: \"" + head(s) + "…\""));
                }
                if (!english) {
                    continue;
                }
                Matcher m = PASSIVE.matcher(s);
                while (m.find()) {
                    String[] parts = m.group().split("\\s+");
                    String participle = parts[parts[1].endsWith("ly") ? 2 : 1].toLowerCase(Locale.ROOT);
                    if (!STATE_WORDS.contains(participle)) {
                        findings.add(new Finding(p.line(), "passive? \"" + m.group() + "\""));
                    }
                }
                m = NOMINAL.matcher(s);
                while (m.find()) {
                    if (!NOMINAL_OK.contains(m.group(1).toLowerCase(Locale.ROOT))) {
                        findings.add(new Finding(p.line(), "nominalization \"" + m.group() + "\" (use the verb)"));
                    }
                }
                m = VAGUE.matcher(s);
                while (m.find()) {
                    findings.add(new Finding(p.line(), "vague word \"" + m.group() + "\""));
                }
                int paren = s.indexOf('(');
                if (paren >= 0) {
                    findings.add(new Finding(p.line(), "parenthesis: \"" + head(s.substring(paren), 50) + "…\""));
                }
                String body = s.endsWith(";") ? s.substring(0, s.length() - 1) : s;
                if (body.contains("—") || body.contains("–") || body.contains(";")) {
                    findings.add(new Finding(p.line(), "dash or semicolon joins clauses"));
                }
                for (String cluster : nounClusters(s, 5)) {
                    findings.add(new Finding(p.line(), "noun cluster \"" + cluster + "\""));
                }
            }
        }
        return findings;
    }

    static List<Paragraph> paragraphs(String text) {
        List<Paragraph> out = new ArrayList<>();
        List<String> para = new ArrayList<>();
        int start = 0;
        boolean inCode = false;
        int lineNo = 0;
        String[] lines = text.split("\n", -1);
        if (lines.length > 0 && lines[0].strip().equals("---")) {
            for (int j = 1; j < lines.length; j++) {
                boolean end = lines[j].strip().equals("---");
                lines[j] = "";
                if (end) {
                    break;
                }
            }
            lines[0] = "";
        }
        for (String raw : lines) {
            lineNo++;
            String line = raw.strip();
            if (FENCE.matcher(line).find()) {
                inCode = !inCode;
                continue;
            }
            if (inCode) {
                continue;
            }
            if (line.isEmpty() || SKIP_LINE.matcher(line).find()) {
                flush(out, para, start);
                continue;
            }
            Matcher item = LIST_ITEM.matcher(line);
            if (item.find()) {
                flush(out, para, start);
                out.add(new Paragraph(lineNo, clean(line.substring(item.end()))));
                continue;
            }
            if (para.isEmpty()) {
                start = lineNo;
            }
            para.add(line);
        }
        flush(out, para, start);
        return out;
    }

    static List<Paragraph> asciidocParagraphs(String text) {
        List<Paragraph> out = new ArrayList<>();
        List<String> para = new ArrayList<>();
        int start = 0;
        String openBlock = null;
        int lineNo = 0;
        for (String raw : text.split("\n", -1)) {
            lineNo++;
            String line = raw.strip();
            if (ADOC_DELIMITERS.contains(line)) {
                flush(out, para, start);
                boolean verbatim = !line.equals("====") && !line.equals("****");
                if (openBlock == null && verbatim) {
                    openBlock = line;
                } else if (line.equals(openBlock)) {
                    openBlock = null;
                }
                continue;
            }
            if (openBlock != null) {
                continue;
            }
            if (line.isEmpty() || ADOC_SKIP_LINE.matcher(line).find()) {
                flush(out, para, start);
                continue;
            }
            Matcher item = LIST_ITEM.matcher(line);
            if (item.find()) {
                flush(out, para, start);
                out.add(new Paragraph(lineNo, clean(asciidocInline(line.substring(item.end())))));
                continue;
            }
            if (para.isEmpty()) {
                start = lineNo;
            }
            para.add(asciidocInline(line));
        }
        flush(out, para, start);
        return out;
    }

    private static String asciidocInline(String line) {
        line = ADOC_MACRO.matcher(line).replaceAll("$1");
        line = ADOC_URL_TEXT.matcher(line).replaceAll("$1");
        line = ADOC_XREF.matcher(line).replaceAll("$1");
        return ADOC_BARE_XREF.matcher(line).replaceAll("$1");
    }

    private static void flush(List<Paragraph> out, List<String> para, int start) {
        if (!para.isEmpty()) {
            out.add(new Paragraph(start, clean(String.join(" ", para))));
            para.clear();
        }
    }

    private static String clean(String p) {
        p = INLINE_CODE.matcher(p).replaceAll("CODE");
        p = LINK.matcher(p).replaceAll("$1");
        p = URL.matcher(p).replaceAll("URL");
        p = VERSION.matcher(p).replaceAll("VER");
        return ABBREV.matcher(p).replaceAll("$1");
    }

    static List<String> sentences(String paragraph) {
        List<String> out = new ArrayList<>();
        for (String s : SENTENCE_END.split(paragraph)) {
            if (!s.isBlank()) {
                out.add(s.strip());
            }
        }
        return out;
    }

    static List<String> nounClusters(String sentence, int min) {
        List<String> found = new ArrayList<>();
        List<String> run = new ArrayList<>();
        Matcher m = TOKEN.matcher(sentence);
        while (m.find()) {
            String t = m.group();
            boolean nounish = NOUNISH.matcher(t).matches() && !t.endsWith("ly") && !t.endsWith("ing")
                    && !t.endsWith("ed") && !STOP.contains(t);
            if (nounish) {
                run.add(t);
            } else {
                if (run.size() >= min) {
                    found.add(String.join(" ", run));
                }
                run.clear();
            }
        }
        if (run.size() >= min) {
            found.add(String.join(" ", run));
        }
        return found;
    }

    private static int count(Pattern p, String s) {
        int n = 0;
        Matcher m = p.matcher(s);
        while (m.find()) {
            n++;
        }
        return n;
    }

    private static String head(String s) {
        return head(s, 70);
    }

    private static String head(String s, int max) {
        return s.length() > max ? s.substring(0, max) : s;
    }
}
