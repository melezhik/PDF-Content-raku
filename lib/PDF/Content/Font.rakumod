role PDF::Content::Font {
    use PDF::COS;
    use PDF::COS::Dict;
    use PDF::Content::FontObj;
    has PDF::Content::FontObj $.font-obj is rw handles <encode decode protect filter font-name height kern stringwidth underline-position underline-thickness>;

    multi method make-font(::?ROLE:D $font-dict, PDF::Content::FontObj:D $font-obj) {
        $font-dict.make-font($font-obj);
    }
    multi method make-font(::?ROLE:U: PDF::COS::Dict:D $font-dict, PDF::Content::FontObj:D $font-obj) {
        $font-dict.^mixin: PDF::Content::Font;
        $font-dict.make-font($font-obj);
    }
    multi method make-font(::?ROLE:D: PDF::Content::FontObj:D $!font-obj) {
        self;
    }
    # formally needed by PDF::Class (PDF::Font::Type1)
    method set-font-obj($!font-obj) is DEPRECATED<make-font> { $!font-obj }

    method cb-finish {
        with $!font-obj {.cb-finish } else { self };
    }
}
