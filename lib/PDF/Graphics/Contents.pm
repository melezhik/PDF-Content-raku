use v6;

use PDF::Graphics;

#| this role is applied to PDF::Graphics::Type::Page, PDF::Graphics::Type::Pattern and PDF::Graphics::Type::XObject::Form
role PDF::Graphics::Contents {

    use PDF::Graphics;
    use PDF::Graphics::Ops :OpNames;

    has PDF::Graphics $!pre-gfx; #| prepended graphics
    method pre-gfx { $!pre-gfx //= PDF::Graphics.new( :parent(self) ) }
    method pre-graphics(&code) { self.pre-gfx.block( &code ) }

    has PDF::Graphics $!gfx;     #| appended graphics
    method gfx(|c) {
	$!gfx //= do {
	    my Pair @ops = self.contents-parse;
	    my $gfx = PDF::Graphics.new( :parent(self), |c );
	    if @ops && ! (@ops[0].key eq OpNames::Save && @ops[*-1].key eq OpNames::Restore) {
		@ops.unshift: OpNames::Save => [];
		@ops.push: OpNames::Restore => [];
	    }
	    $gfx.ops: @ops;
	    $gfx;
	}
    }
    method graphics(&code) { self.gfx.block( &code ) }
    method text(&code) { self.gfx.text( &code ) }

    method contents-parse(Str $contents = $.contents ) {
        PDF::Graphics.parse($contents);
    }

    method contents returns Str {
	$.decoded // '';
    }

    method render(&callback) {
	die "too late to install render callback"
	    if $!gfx;
	self.gfx(:&callback);
    }

    method cb-finish {

        my $prepend = $!pre-gfx && $!pre-gfx.ops
            ?? $!pre-gfx.content ~ "\n"
            !! '';

        my $append = $!gfx && $!gfx.ops
            ?? $!gfx.content
            !! '';

        self.decoded = $prepend ~ $append;
    }

}
