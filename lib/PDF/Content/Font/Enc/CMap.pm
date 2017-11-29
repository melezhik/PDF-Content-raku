use v6;
use PDF::DAO::Stream;

class PDF::Content::Font::Enc::CMap {
    has uint32 @!to-unicode;

    submethod TWEAK(PDF::DAO::Stream :$cmap!) {

        for $cmap.decoded.Str.lines {
            if /:s^ \d+ beginbfrange/ ff /^endbfrange/ {
                if /:s [ '<' $<r>=[<xdigit>+] '>' ] ** 3 / {
                    my uint ($from, $to, $code-point) = @<r>.map: { :16(.Str) };

                    for $from .. $to {
                        @!to-unicode[$_] = $code-point++;
                    }
                }
            }
            if /:s^ \d+ beginbfchar/ ff /^endbfchar/ {
                if /:s [ '<' $<r>=[<xdigit>+] '>' ] ** 2 / {
                    my uint ($from, $code-point) = @<r>.map: { :16(.Str) };
                    @!to-unicode[$from] = $code-point;
                }
            }
        }
    }

    multi method decode(Str $s, :$str! --> Str) {
        $s.ords.map({@!to-unicode[$_]}).grep({$_}).map({.chr}).join;
    }
    multi method decode(Str $s --> buf32) {
        buf32.new: $s.ords.map({@!to-unicode[$_]}).grep: {$_};
    }
}
