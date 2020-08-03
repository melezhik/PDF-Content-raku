use v6;
use Test;
plan 5;
use lib 't';
use PDFTiny;
use PDF::Content::Ops;
use PDF::Grammar;
my PDF::Content $g = PDFTiny.new.add-page.gfx;

lives-ok {$g.ops("BT BX 10 10 Td EX ET")}, 'regular op, extensions enabled';
todo "PDF::Grammar v0.2.4+ needed for extended op tests", 4
    unless PDF::Grammar.^ver >= v0.2.4;
quietly throws-like {$g.ops("(unknown-op) BAZINGA")}, X::PDF::Content::OP::Unknown, :message("Unknown content operator: 'BAZINGA'");
lives-ok {$g.ops("BX (extended-op) BAZINGA EX");}, 'extended content lives';
throws-like {$g.ops('EX')},  X::PDF::Content::OP::BadNesting, :message("Bad nesting; 'EX' (EndExtended) operator not matched by preceeding 'BX' (BeginExtended)");
is $g.Str.lines.>>.trim.join('|'), 'BT|BX|10 10 Td|EX|ET|BX|(extended-op) BAZINGA|EX|EX', 'rendered content';
