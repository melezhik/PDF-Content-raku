use v6;

use PDF::Writer;
use PDF::DAO::Util :from-ast;

role PDF::Content::Ops {

    has &.callback is rw;
    has Pair @!ops;
    has Bool $.comment-ops is rw = False;
    has Bool $.strict = True;
    has $.parent;

=begin pod

This role implements methods and mnemonics for the full operator table, as defined in specification [PDF 1.7 Appendix A]:

=begin table
* Operator * | *Mnemonic* | *Operands* | *Description*
b | CloseFillStroke | — | Close, fill, and stroke path using nonzero winding number rule
B | FillStroke | — | Fill and stroke path using nonzero winding number rule
b* | CloseEOFillStroke | — | Close, fill, and stroke path using even-odd rule
B* | EOFillStroke | — | Fill and stroke path using even-odd rule
BDC | BeginMarkedContentDict | tag properties | (PDF 1.2) Begin marked-content sequence with property list
BI | BeginImage | — | Begin inline image object
BMC | BeginMarkedContent | tag | (PDF 1.2) Begin marked-content sequence
BT | BeginText | — | Begin text object
BX | BeginIgnore | — | (PDF 1.1) Begin compatibility section
c | CurveTo | x1 y1 x2 y2 x3 y3 | Append curved segment to path (three control points)
cm | ConcatMatrix | a b c d e f | Concatenate matrix to current transformation matrix
CS | SetStrokeColorSpace | name | (PDF 1.1) Set color space for stroking operations
cs | SetFillColorSpace | name | (PDF 1.1) Set color space for nonstroking operations
d | SetDash | dashArray dashPhase | Set line dash pattern
d0 | SetCharWidth | wx wy | Set glyph width in Type 3 font
d1 | SetCharWidthBBox | wx wy llx lly urx ury | Set glyph width and bounding box in Type 3 font
Do | XObject | name | Invoke named XObject
DP | MarkPointDict | tag properties | (PDF 1.2) Define marked-content point with property list
EI | EndImage | — | End inline image object
EMC | EndMarkedContent | — | (PDF 1.2) End marked-content sequence
ET | EndText | — | End text object
EX | EndIgnore | — | (PDF 1.1) End compatibility section
f | Fill | — | Fill path using nonzero winding number rule
F | FillObsolete | — | Fill path using nonzero winding number rule (obsolete)
f* | EOFill| — | Fill path using even-odd rule
G | SetStrokeGray | gray | Set gray level for stroking operations
g | SetFillGray | gray | Set gray level for nonstroking operations
gs | SetGraphicsState | dictName | (PDF 1.2) Set parameters from graphics state parameter dictionary
h | ClosePath | — | Close subpath
i | SetFlat | flatness | Set flatness tolerance
ID | ImageData | — | Begin inline image data
j | SetLineJoin | lineJoin| Set line join style
J | SetLineCap | lineCap | Set line cap style
K | SetStrokeCMYK | c m y k | Set CMYK color for stroking operations
k | SetFillCMYK | c m y k | Set CMYK color for nonstroking operations
l | LineTo | x y | Append straight line segment to path
m | MoveTo | x y | Begin new subpath
M | SetMiterLimit | miterLimit | Set miter limit
MP | MarkPoint | tag | (PDF 1.2) Define marked-content point
n | EndPath | — | End path without filling or stroking
q | Save | — | Save graphics state
Q | Restore | — | Restore graphics state
re | Rectangle | x y width height | Append rectangle to path
RG | SetStrokeRGB | r g b | Set RGB color for stroking operations
rg | SetFillRGB | r g b | Set RGB color for nonstroking operations
ri | SetRenderingIntent | intent | Set color rendering intent
s | CloseStroke | — | Close and stroke path
S | Stroke | — | Stroke path
SC | SetStrokeColor | c1 … cn | (PDF 1.1) Set color for stroking operations
sc | SetFillColor | c1 … cn | (PDF 1.1) Set color for nonstroking operations
SCN | SetStrokeColorN | c1 … cn [name] | (PDF 1.2) Set color for stroking operations (ICCBased and special color spaces)
scn | SetFillColorN | c1 … cn [name] | (PDF 1.2) Set color for nonstroking operations (ICCBased and special color spaces)
sh | ShFill | name | (PDF 1.3) Paint area defined by shading pattern
T* | TextNextLine | — | Move to start of next text line
Tc | SetCharSpacing| charSpace | Set character spacing
Td | TextMove | tx ty | Move text position
TD | TextMoveSet | tx ty | Move text position and set leading
Tf | SetFont | font size | Set text font and size
Tj | ShowText | string | Show text
TJ | ShowSpaceText | array | Show text, allowing individual glyph positioning
TL | SetTextLeading | leading | Set text leading
Tm | SetTextMatrix | a b c d e f | Set text matrix and text line matrix
Tr | SetTextRender | render | Set text rendering mode
Ts | SetTextRise | rise | Set text rise
Tw | SetWordSpacing | wordSpace | Set word spacing
Tz | SetHorizScaling | scale | Set horizontal text scaling
v | CurveToInitial | x2 y2 x3 y3 | Append curved segment to path (initial point replicated)
w | SetLineWidth | lineWidth | Set line width
W | Clip | — | Set clipping path using nonzero winding number rule
W* | EOClip | — | Set clipping path using even-odd rule
y | CurveToFinal | x1 y1 x3 y3 | Append curved segment to path (final point replicated)
' | MoveShowText | string | Move to next line and show text
" | MoveSetShowText | aw ac string | Set word and character spacing, move to next line, and show text

=end table

=end pod

    #| some convenient mnemomic names
    my Str enum OpNames is export(:OpNames) «
        :BeginImage<BI> :ImageData<ID> :EndImage<EI>
        :BeginMarkedContent<BMC> :BeginMarkedContentDict<BDC>
        :EndMarkedContent<EMC> :BeginText<BT> :EndText<ET>
        :BeginIgnore<BX> :EndIgnore<EX> :CloseEOFillStroke<b*>
        :CloseFillStroke<b> :EOFillStroke<B*> :FillStroke<B>
        :CurveTo<c> :ConcatMatrix<cm> :SetFillColorSpace<cs>
        :SetStrokeColorSpace<CS> :SetDash<d> :SetCharWidth<d0>
        :SetCharWidthBBox<d1> :XObject<Do> :MarkPointDict<DP>
        :EOFill<f*> :Fill<f> :FillObsolete<F> :SetStrokeGray<G>
        :SetFillGray<g> :SetGraphicsState<gs> :ClosePath<h>
        :SetFlat<i> :SetLineJoin<j> :SetLineCap<J> :SetFillCMYK<k>
        :SetStrokeCMYK<K> :LineTo<l> :MoveTo<m> :SetMiterLimit<M>
        :MarkPoint<MP> :EndPath<n> :Save<q> :Restore<Q> :Rectangle<re>
        :SetFillRGB<rg> :SetStrokeRGB<RG> :SetRenderingIntent<ri>
        :CloseStroke<s> :Stroke<S> :SetStrokeColor<SC>
        :SetFillColor<sc> :SetFillColorN<scn> :SetStrokeColorN<SCN>
        :ShFill<sh> :TextNextLine<T*> :SetCharSpacing<Tc>
        :TextMove<Td> :TextMoveSet<TD> :SetFont<Tf> :ShowText<Tj>
        :ShowSpaceText<TJ> :SetTextLeading<TL> :SetTextMatrix<Tm>
        :SetTextRender<Tr> :SetTextRise<Ts> :SetWordSpacing<Tw>
        :SetHorizScaling<Tz> :CurveToInitial<v> :EOClip<W*> :Clip<W>
        :SetLineWidth<w> :CurveToFinal<y> :MoveSetShowText<">
        :MoveShowText<'>
    »;

    my constant %OpCode = OpNames.enums.invert.Hash;

    # See [PDF 1.7 TABLE 4.1 Operator categories]
    my constant GeneralGraphicOps = set <w J j M d ri i gs>;
    my constant SpecialGraphicOps = set <q Q cm>;
    my constant PathOps = set <m l c v y h re>;
    my constant PaintingOps = set <S s f F f* B B* b b* n>;
    my constant ClippingOps = set <W W*>;
    my constant TextObjectOps = set <BT ET>;
    my constant TextStateOps = set <Tc Tw Tz TL Tf Tr Ts>;
    my constant TextOps = set <T* Td TD Tj TJ Tm>;
    my constant ColorOps = set <CS cs SC SCN sc scn G g RG rg K k>;
    my constant MarkedContentOps = set <MP DP BMC BDC EMC>;

    #| [PDF 1.7 TABLE 5.3 Text rendering modes]
    my Int enum TextMode is export(:TextMode) «
	:FillText(0) :OutlineText(1) :FillOutlineText(2)
        :InvisableText(3) :FillClipText(4) :OutlineClipText(5)
        :FillOutlineClipText(6) :ClipText(7)
    »;

    # *** TEXT STATE ***
    has Numeric $!Tc = 0;    #| character spacing
    has Numeric $!Tw = 0;    #| word spacing
    has Numeric $!Th = 100;  #| horizontal scaling
    has Numeric $!Tl = 0;    #| leading
    has Numeric $!Tmode = 0; #| text rendering mode
    has Numeric $!Trise = 0; #| text rise
    has Hash $!Tf;           #| font dictionary
    has Numeric $!Tfs;       #| font size
    has Numeric @!Tm  = [ 1, 0, 0, 1, 0, 0, ];      #| text matrix
    has Numeric @!CTM = [ 1, 0, 0, 1, 0, 0, ];      #| graphics matrix;

    # Extended Graphics States (Resource /ExtGState entries)
    # See [PDF 1.7 TABLE 4.8 Entries in a graphics state parameter dictionary]
    my enum ExtGState is export(:ExtGState) «
	:line-width<LW>
	:line-cap<LC>
	:line-join-style<LJ>
	:miter-limit<ML>
	:dash-pattern<D>
	:rendering-intent<RI>
	:over-print-paint<OP>
	:over-print-stroke<op>
	:over-print-mode<OPM>
	:font<Font>
	:black-generation-old<BG>
	:black-generation<BG2>
	:under-cover-removal-function-old<UCR>
	:under-cover-removal-function<UCR2>
	:transfer-function-old<TR>
	:transfer-function<TR2>
	:halftone<HT>
	:flatness-tolerance<FT>
	:smoothness-tolerance<ST>
        :stroke-adjust<SA>
        :blend-mode<BM>
        :soft-mask<SMask>
	:stroke-alpha<CA>
	:fill-alpha<ca>
	:alpha-source<AIS>
	:text-knockout<TK>
    »;

    has @!gsave;
    has @!tags;

    method !proxy(\var, $setter) {
        Proxy.new(
            FETCH => sub ($) { var },
            STORE => sub ($,*@v) {
                self."$setter"(|@v);
            });
    }

    method TextMatrix   is rw { self!proxy(@!Tm, 'SetTextMatrix') }
    method CharSpacing  is rw { self!proxy($!Tc, 'SetCharSpacing')  }
    method WordSpacing  is rw { self!proxy($!Tw, 'SetWordSpacing')  }
    method HorizScaling is rw { self!proxy($!Th, 'SetHorizScaling')  }
    method TextLeading  is rw { self!proxy($!Tl, 'SetTextLeading')  }
    method TextRender   is rw { self!proxy($!Tmode, 'SetTextRender') }
    method TextRise     is rw { self!proxy($!Trise, 'SetTextRise') }
    method Font           { $!Tf  }
    method FontSize       { $!Tfs }
    method GraphicsMatrix { @!CTM  }

    # States and transitions in [PDF 1.4 FIGURE 4.1 Graphics objects]
    my enum GraphicsContext is export(:GraphicsContext) <Path Text Clipping Page Shading External Image>;

    has GraphicsContext $.context = Page;

    method !track-context(Str $op, $last-op) {
        my $transition = do given $op {

            when 'BT'       { [Page, Text] }
            when 'ET'       { [Text, Page] }

            when 'BI'       { [Page, Image] }
            when 'EI'       { [Image, Page] }

            when 'BX'       { [Page, External] }
            when 'EX'       { [External, Page] }

            when 'W' | 'W*' { [Path, Clipping] }
            when 'm' | 're' { [Page, Path] }
            when 'Do'       { [Page, Page ] }
            when $op ∈ PaintingOps { [Clipping | Path, Page] }
        }

       my Bool $ok-here;

       if $transition {
           $ok-here = ?($transition[0] == $!context);
           $!context = $transition[1];
       }
       else {
           $ok-here = do given $!context {
               when Path     { $op ∈ PathOps }
               when Text     { ?($op ∈ TextOps | TextStateOps | GeneralGraphicOps | ColorOps | MarkedContentOps) }
               when Page     { ?($op ∈ TextStateOps | SpecialGraphicOps | GeneralGraphicOps | ColorOps | MarkedContentOps) }
               when Image    { $op eq 'ID' }
               default       { False }
           }
       }

       warn "unexpected '$op' operation " ~ ($last-op ?? "(following '$last-op')" !! '(first operation)')
	   unless $ok-here;
    }

    my %Ops = BEGIN %(

        #| BI dict ID stream EI
        'BI' => sub ($op, Hash $dict = {}) {
            $op => [ :$dict ];
        },

        'ID' => sub ($op, Str $encoded = '') {
            $op => [ :$encoded ];
        },

        'EI' => sub ($op) { $op => [] },

        'BX'|'EX' => sub ($op, |c) {
            die "todo ignored content BX [lines] EX: $op";
        },

        'BT'|'ET'|'EMC'|'BX'|'EX'|'b*'|'b'|'B*'|'B'|'f*'|'F'|'f'
            | 'h'|'n'|'q'|'Q'|'s'|'S'|'T*'|'W*'|'W' => sub ($op) {
            $op => [];
        },

        #| tag                     BMC | MP
        #| name                    cs | CS | Do | sh
        #| dictname                gs
        #| intent                  ri
        'BMC'|'cs'|'CS'|'Do'|'gs'|'MP'|'ri'|'sh' => sub ($op, Str $name!) {
            $op => [ :$name ]
        },

        #| string                  Tj | '
        'Tj' | "'" => sub ($op, Str $literal!) {
            $op => [ :$literal ]
         },

        #| array                   TJ
        'TJ' => sub (Str $op, Array $args!) {
            my @array = $args.map({
                when Str     { :literal($_) }
                when Numeric { :int(.Int) }
                when Pair    { $_ }
                default {die "invalid entry in $op array: {.perl}"}
            });
            $op => [ :@array ];
        },

        'Tf' => sub (Str $op, Str $name!, Numeric $real!) {
            $op => [ :$name, :$real ]
        },

        #| name dict              BDC | DP
        'BDC'|'DP' => sub (Str $op, Str $name!, Hash $dict!) {
            $op => [ :$name, :$dict ]
        },

        #| dashArray dashPhase    d
        'd' => sub (Str $op, Array $args!, Numeric $real!) {
            my @array = $args.map({
                when Numeric { :real($_) }
                when Pair    { $_ }
                default {die "invalid entry in $op array: {.perl}"}
            });
            $op => [ :@array, :$real ];
        },

        #| flatness               i
        #| gray                   g | G
        #| miterLimit             m
        #| charSpace              Tc
        #| leading                TL
        #| rise                   Ts
        #| wordSpace              Tw
        #| scale                  Tz
        #| lineWidth              w
        'i'|'g'|'G'|'M'|'Tc'|'TL'|'Ts'|'Tw'|'Tz'|'w' => sub ($op, Numeric $real!) {
            $op => [ :$real ]
        },

        #| lineCap                J
        #| lineJoin               j
        #| render                 Tr
        'j'|'J'|'Tr' => sub ($op, UInt $int!) {
            $op => [ :$int ]
        },

        #| x y                    m l
        #| wx wy                  d0
        #| tx ty                  Td TD
        'd0'|'l'|'m'|'Td'|'TD' => sub ($op, Numeric $n1!, Numeric $n2!) {
            $op => [ :real($n1), :real($n2) ]
        },

        #| aw ac string           "
        '"' => sub (Str $op, Numeric $n1!, Numeric $n2!, Str $literal! ) {
            $op => [ :real($n1), :real($n2), :$literal ]
        },

        #| r g b                  rg | RG
        'rg'|'RG' => sub (Str $op, Numeric $n1!,
                          Numeric $n2!, Numeric $n3!) {
            $op => [ :real($n1), :real($n2), :real($n3) ]
        },

        #| c m y k                k | K
        #| x y width height       re
        #| x2 y2 x3 y3            v y
        'k'|'K'|'re'|'v'|'y' => sub (Str $op, Numeric $n1!,
                                             Numeric $n2!, Numeric $n3!, Numeric $n4!) {
            $op => [ :real($n1), :real($n2), :real($n3), :real($n4) ]
        },

        #| x1 y1 x2 y2 x3 y3      c | cm
        #| wx wy llx lly urx ury  d1
        #| a b c d e f            Tm
        'c'|'cm'|'d1'|'Tm' => sub (Str $op,
            Numeric $n1!, Numeric $n2!, Numeric $n3!, Numeric $n4!, Numeric $n5!, Numeric $n6!) {
            $op => [ :real($n1), :real($n2), :real($n3), :real($n4), :real($n5), :real($n6) ]
        },

        # c1, ..., cn             sc | SC
        'sc'|'SC' => sub (Str $op, *@args is copy) {

            die "too few arguments to: $op"
                unless @args;

            @args = @args.map({ 
                when Pair    {$_}
                when Numeric { :real($_) }
                default {
                    die "$op: bad argument: {.perl}"
                }
            });

            $op => [ @args ]
        },

        # c1, ..., cn [name]      scn | SCN
        'scn'|'SCN' => sub (Str $op, *@_args) {

            my @args = @_args;
            # scn & SCN have an optional trailing name
            my Str $name = @args.pop
                if +@args && @args[*-1] ~~ Str;

            die "too few arguments to: $op"
                unless $name.defined || @args;

            @args = @args.map({ 
                when Pair    {$_}
                when Numeric { :real($_) }
                default {
                    die "$op: bad argument: {.perl}"
                }
            });

            @args.push: (:$name) if $name.defined;

            $op => [ @args ]
        },
     );

    proto sub op(|c) returns Pair {*}
    #| semi-raw and a little dwimmy e.g:  op('TJ' => [[:literal<a>, :hex-string<b>, 'c']])
    #|                                     --> :TJ( :array[ :literal<a>, :hex-string<b>, :literal<c> ] )
    multi sub op(Pair $raw!) {
        my Str $op = $raw.key;
        my List $input_vals = $raw.value;
        # validate the operation and get fallback coercements for any missing pairs
        my subset Comment of Pair where {.key eq 'comment'}
        my @vals = $raw.value.grep({$_ !~~ Comment}).map({ from-ast($_) });
        my $opn = op($op, |@vals);
	my $coerced_vals = $opn.value;

	my @ast-values = $input_vals.pairs.map({
	    .value ~~ Pair
		?? .value
		!! $coerced_vals[.key]
	});
	$op => [ @ast-values ];
    }

    multi sub op(Str $op, |c) is default {
        with %Ops{$op} {
            .($op,|c);
        }
        else {
            die "unknown content operator: $op";
        }
    }

    method op(*@args is copy) {
        my $opn = op(|@args);
	my Str $op-name;

        if $opn ~~ Pair {
	    $op-name = $opn.key.Str;
	    @args = [ $opn.value.map: *.value ];
	}
	else {
	    $op-name = $opn.Str;
	}

        if $!context == Text {
	    warn "special graphics operation '$op-name' used in a BT ... ET text block"
	        if $op-name ∈ SpecialGraphicOps;
        }
        else {
            warn "text operation '$op-name' outside of a BT ... ET text block\n"
	        if $op-name ∈ TextOps;
        }

	# not illegal just bad practice. makes it harder to later edit/reuse this content stream
	# and may upset downstream utilities
	if $!strict {
	    if !@!gsave {
		warn "graphics operation '$op-name' outside of a q ... Q graphics block\n"
		    if $op-name ∈ GeneralGraphicOps | ColorOps
		    || $op-name eq 'cm';
	    }
	}

        my Str $last-op = @!ops[*-1].key
	    if @!ops;

	@!ops.push($opn);
        self!track-context($op-name, $last-op);
        self.track-graphics($op-name, |@args );
        .($op-name, |@args, :gfx(self) )
	    with self.callback;
        $opn.value.push: (:comment(%OpCode{$op-name}))
            if $!comment-ops;
	$opn;
    }

    multi method ops(Str $ops!) {
	$.ops( self.parse($ops) );
    }

    multi method ops(Array $ops?) {
	if $ops.defined {
	    self.op($_)
		for $ops.list
	}
        @!ops;
    }

    method parse(Str $content) {
	use PDF::Grammar::Content;
	use PDF::Grammar::Content::Actions;
	state $actions //= PDF::Grammar::Content::Actions.new;
	PDF::Grammar::Content.parse($content, :$actions)
	    // die "unable to parse content stream: $content";
	$/.ast
    }

    multi method track-graphics('q') {
        my @Tm = @!Tm;
        my @CTM = @!CTM;
        my %gstate = :$!Tc, :$!Tw, :$!Th, :$!Tl, :$!Tmode, :$!Trise, :$!Tf, :$!Tfs, :@Tm, :@CTM;
        @!gsave.push: %gstate;
    }
    multi method track-graphics('Q') {
        die "bad nesting; Restore(Q) operator not matched by preceeding Save(q) operator in PDF content\n"
            unless @!gsave;
        my %gstate = @!gsave.pop;
        $!Tc    = %gstate<Tc>;
        $!Tw    = %gstate<Tw>;
        $!Th    = %gstate<Th>;
        $!Tl    = %gstate<Tl>;
        $!Tmode = %gstate<Tmode>;
        $!Trise = %gstate<Trise>;
        $!Tf    = %gstate<Tf>;
        $!Tfs   = %gstate<Tfs>;
        @!Tm    = @(%gstate<Tm>);
        @!CTM   = @(%gstate<CTM>);
	Restore;
    }
    multi method track-graphics('cm', *@transform) {
        use PDF::Content::Util::TransformMatrix;
        @!CTM = PDF::Content::Util::TransformMatrix::multiply(@!CTM, @transform);
    }
    multi method track-graphics('ET') {
        @!Tm = [ 1, 0, 0, 1, 0, 0, ];
    }
    multi method track-graphics('BMC', Str $name!) {
	@!tags.push: 'BMC';
    }
    multi method track-graphics('BDC', *@args) {
	@!tags.push: 'BDC';
    }
    multi method track-graphics('EMC') {
	die "closing EMC without opening BMC or BDC in PDF content\n"
	    unless @!tags;
	@!tags.pop;
    }
    multi method track-graphics('gs', Str $key) {
        with self.parent {
            with .resource-entry('ExtGState', $key) {
                with .<Font> { $!Tf = ~ .[0]; $!Tfs = + .[1] }
            }
            else {
                die "unknown extended graphics state: /$key"
            }
        }
    }
    multi method track-graphics('Tc', Numeric $!Tc!) {
    }
    multi method track-graphics('Tw', Numeric $!Tw!) {
    }
    multi method track-graphics('Tz', Numeric $!Th!) {
    }
    multi method track-graphics('TL', Numeric $!Tl!) {
    }
    multi method track-graphics('Tf', Str $key, Numeric $!Tfs!) {
        with self.parent {
            with .resource-entry('Font', $key) {
                $!Tf = $_;
            }
            else {
                die "unknown font key: /$!Tf"
            }
        }
    }
    multi method track-graphics('Ts', Numeric $!Trise!) {
    }
    multi method track-graphics('Tm', *@!Tm) {
    }
    multi method track-graphics('Td', Numeric $tx!, Numeric $ty) {
        @!Tm[4] += $tx;
        @!Tm[5] += $ty;
    }
    multi method track-graphics('TD', Numeric $tx!, Numeric $ty) {
        $!Tl = - $ty;
        $.track-graphics(TextMove, $tx, $ty);
    }
    multi method track-graphics('T*') {
        $.track-graphics(TextMove, 0, $!Tl);
    }
    multi method track-graphics(*@args) is default {}

    method finish {
	die "Unclosed @!tags[] at end of content stream\n"
	    if @!tags;
	die "q(Save) unmatched by closing Q(Restore) at end of content stream\n"
	    if @!gsave;
        warn "unexpected end of content stream"
	    unless $!context == Page;
    }

    #| serialize content. indent blocks for readability
    method content {
        use PDF::Writer;
	my constant Openers = 'q' | 'BT' | 'BMC' | 'BDC' | 'BX';
	my constant Closers = 'Q' | 'ET' | 'EMC' | 'EX';

	$.finish;
        my $writer = PDF::Writer.new;
	my UInt $nesting = 0;

        @!ops.map({
	    my $op = ~ .key;

	    $nesting-- if $nesting && $op eq Closers;
	    $writer.indent = '  ' x $nesting;
	    $nesting++ if $op eq Openers;

	    $writer.indent ~ $writer.write: :content($_);
	}).join: "\n";
    }

    # e.g. $.Restore :== $.op('Q', [])
    multi method FALLBACK(Str $op-name where {OpNames.enums{$op-name}:exists},
			  *@args,
	) {
	my $op = OpNames.enums{$op-name};
	my &op-meth = method (*@a) { self.op($op, |@a) };
        self.WHAT.^add_method($op-name, &op-meth );
        self."$op-name"(|@args);
    }

    multi method FALLBACK($name) is default { die "unknown operator/method: $name\n" }

}
