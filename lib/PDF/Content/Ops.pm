use v6;

my role GraphicsAtt {
    has Str $.accessor-name is rw;
    method compose(Mu \package) {
        my \meth-name = self.accessor-name;
        nextsame
            if package.^declares_method(meth-name)
            || ! (self.has_accessor && self.rw);
        my \setter = 'Set' ~ meth-name;
        package.^add_method( meth-name, sub (\obj) is rw { obj.graphics-accessor( self, setter ); } );
    }
}

my role ExtGraphicsAtt {
    has Str $.accessor-name is rw;
    has Str $.key is rw;
    method compose(Mu \package) {
        my \meth-name = self.accessor-name;
        nextsame
            if package.^declares_method(meth-name)
            || ! (self.has_accessor && self.rw);
        package.^add_method( meth-name, sub (\obj) is rw { obj.ext-graphics-accessor( self, self.key ); } );
    }
}

class X::PDF::Content is Exception {
}

class X::PDF::Content::OP::Unexpected
    is X::PDF::Content {
    has Str $.op is required;
    has Str $.type is required;
    has Str $.mnemonic is required;
    has Str $.where is required;
    method message { "$!type operation '$.op' ($!mnemonic) used $!where" }
}

class X::PDF::Content::OP::BadNesting
    is X::PDF::Content {
    has Str $.op is required;
    has Str $.mnemonic is required;
    has Str $.opener;
    method message {
        "Bad nesting; '$!op' ($!mnemonic) operator not matched by preceeding $!opener"
    }
 }

class X::PDF::Content::OP::Error
    is X::PDF::Content {
    has Str $.op is required;
    has Str $.mnemonic is required;
    has Exception $.error is required;
    method message { "Error processing '$.op' ($!mnemonic) operator: {$!error.message}" }
}

class X::PDF::Content::OP::Unknown
    is X::PDF::Content {
    has Str $.op is required;
    method message { "Unknown content operator: '$.op'" }
}

class X::PDF::Content::OP::BadArrayArg
    is X::PDF::Content {
    has Str $.op is required;
    has $.arg is required;
    has Str $.mnemonic is required;
    method message { "Invalid entry in '$.op' ($!mnemonic) array: {$!arg.perl}" }
}

class X::PDF::Content::OP::BadArg
    is X::PDF::Content {
    has Str $.op is required;
    has $.arg is required;
    has Str $.mnemonic is required;
    method message { "Bad '$.op' ($!mnemonic) argument: {$!arg.perl}" }
}

class X::PDF::Content::OP::TooFewArgs
    is X::PDF::Content {
    has Str $.op is required;
    has Str $.mnemonic is required;
    method message { "Too few arguments to '$.op' ($!mnemonic)" }
}

class X::PDF::Content::OP::ArgCount
    is X::PDF::Content {
    has Str $.message is required;
}

class X::PDF::Content::Unclosed
    is X::PDF::Content {
    has Str $.message is required;
}

class X::PDF::Content::ParseError
    is X::PDF::Content {
    has Str $.content is required;
    method message {"Unable to parse content stream: $!content";}
}

class X::PDF::Content::UnknownResource
    is X::PDF::Content {
    has Str $.type is required;
    has Str $.key is required;
    method message { "Unknown $!type resource: /$!key" }
}

class PDF::Content::Ops {

    use PDF::Writer;
    use PDF::COS;
    use PDF::COS::Util :from-ast, :to-ast;
    use PDF::Content::Matrix :inverse, :multiply, :is-identity;
    use PDF::Content::Tag;

    has Routine @.callback is rw;
    has Pair @.ops;
    has Bool $.comment-ops is rw = False;
    has Bool $.strict is rw = True;
    has $.parent handles <resource-key resource-entry core-font use-font resources xobject-form tiling-pattern use-pattern width height>;

    # some convenient mnemomic names
    my Str enum OpCode is export(:OpCode) «
        :BeginImage<BI> :ImageData<ID> :EndImage<EI>
        :BeginMarkedContent<BMC> :BeginMarkedContentDict<BDC>
        :EndMarkedContent<EMC> :BeginText<BT> :EndText<ET>
        :BeginExtended<BX> :EndExtended<EX> :CloseEOFillStroke<b*>
        :CloseFillStroke<b> :EOFillStroke<B*> :FillStroke<B>
        :CurveTo<c> :ConcatMatrix<cm> :SetFillColorSpace<cs>
        :SetStrokeColorSpace<CS> :SetDashPattern<d> :SetCharWidth<d0>
        :SetCharWidthBBox<d1> :XObject<Do> :MarkPointDict<DP>
        :EOFill<f*> :Fill<f> :FillObsolete<F> :SetStrokeGray<G>
        :SetFillGray<g> :SetGraphicsState<gs> :ClosePath<h>
        :SetFlatness<i> :SetLineJoin<j> :SetLineCap<J> :SetFillCMYK<k>
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

    my constant %OpName is export(:OpName) = OpCode.enums.invert.Hash;

    # See [PDF 1.7 TABLE 4.1 Operator categories]
    my constant GeneralGraphicOps = set <w J j M d ri i gs>;
    my constant SpecialGraphicOps = set <q Q cm>;
    my constant PathOps = set <m l c v y h re>;
    my constant PaintingOps = set <S s f F f* B B* b b* n>;
    my constant ClippingOps = set <W W*>;
    my constant TextObjectOps = set <BT ET>;
    my constant TextStateOps = set <Tc Tw Tz TL Tf Tr Ts>;
    my constant TextOps = set <T* Td TD Tj TJ Tm ' ">;
    my constant ColorOps = set <CS cs SC SCN sc scn G g RG rg K k>;
    my constant MarkedContentOps = set <MP DP BMC BDC EMC>;
    my constant CompatOps = set <BX EX>;
    my constant FontOps = set <d0 d1>;

    # Extended Graphics States (Resource /ExtGState entries)
    # See [PDF 1.7 TABLE 4.8 Entries in a graphics state parameter dictionary]
    # These match PDF::ExtGState from PDF::Class
    my enum ExtGState is export(:ExtGState) «

	:LineWidth<LW>
	:LineCap<LC>
	:LineJoinStyle<LJ>
	:MiterLimit<ML>
	:DashPattern<D>
	:RenderingIntent<RI>
	:OverPrintPaint<OP>
	:OverPrintStroke<op>
	:OverPrintMode<OPM>
	:Font<Font>
	:BlackGeneration-old<BG>
	:BlackGeneration<BG2>
	:UnderColorRemoval-old<UCR>
	:UnderColorRemoval<UCR2>
	:TransferFunction-old<TR>
	:TransferFunction<TR2>
	:Halftone<HT>
	:Flatness<FT>
	:Smoothness<SM>
        :StrokeAdjust<SA>
        :BlendMode<BM>
        :SoftMask<SMask>
	:StrokeAlpha<CA>
	:FillAlpha<ca>
	:AlphaSource<AIS>
	:TextKnockout<TK>
    »;

    # [PDF 1.7 TABLE 5.3 Text rendering modes]
    my Int enum TextMode is export(:TextMode) «
	:FillText(0) :OutlineText(1) :FillOutlineText(2)
        :InvisableText(3) :FillClipText(4) :OutlineClipText(5)
        :FillOutlineClipText(6) :ClipText(7)
    »;

    my Int enum LineCaps is export(:LineCaps) «
	:ButtCaps(0) :RoundCaps(1) :SquareCaps(2)
    »;

    my Int enum LineJoin is export(:LineJoin) «
	:MiterJoin(0) :RoundJoin(1) :BevelJoin(2)
    »;

    method graphics-accessor(Attribute $att, $setter) is rw {
        Proxy.new(
            FETCH => sub ($) { $att.get_value(self) },
            STORE => sub ($,*@v) {
                self."$setter"(|@v)
                    unless [$att.get_value(self).list] eqv @v;
            });
    }

    method ext-graphics-accessor(Attribute $att, $key) is rw {
        Proxy.new(
            FETCH => sub ($) { $att.get_value(self) },
            STORE => sub ($,\v) {
                unless $att.get_value(self) eqv v {
                    with self.parent {
                        my  &grepper = sub (Hash $_) {
                            .keys.grep(* ne 'Type') eqv ($key, ) && .{$key} eqv v;
                        }
                        my $gs = .find-resource(&grepper, :type<ExtGState>)
                            // PDF::COS.coerce({ :Type{ :name<ExtGState> }, $key => v });
                        my Str $gs-entry = .resource-key($gs, :eqv);
	                self.SetGraphicsState($gs-entry);
                    }
                    else {
                        warn "unable to set extended graphics state - no parent";
                    }
                }
            });
    }

    my Method %PostOp;
    my Attribute %GraphicVars;
    my Str %ExtGStateEntries;

    multi trait_mod:<is>(Attribute $att, :$graphics!) {
        $att does GraphicsAtt;
        $att.accessor-name = $att.name.substr(2);
        %GraphicVars{$att.accessor-name} = $att;

        if $graphics ~~ Method {
            my \setter = 'Set' ~ $att.accessor-name;
            my Str \op = OpCode.enums{setter}
                or die "No OpCode::{setter} entry for {$att.name}";
            %PostOp{op} = $graphics;
        }
        else {
	    warn "ignoring graphics trait"
                unless $graphics ~~ Bool;
        }
    }

    multi trait_mod:<is>(Attribute $att, :$ext-graphics!) {
        $att does ExtGraphicsAtt;
        my $method-name = $att.name.substr(2);
        $att.accessor-name = $method-name;
        %GraphicVars{$method-name} = $att;
        $att.key = ExtGState.enums{$method-name}
            or die "no ExtGState::$method-name enumeration";
        %ExtGStateEntries{$method-name} = $att.key;
    }

    # *** TEXT STATE ***
    has Numeric $.CharSpacing   is graphics(method ($!CharSpacing)  {}) is rw = 0;
    has Numeric $.WordSpacing   is graphics(method ($!WordSpacing)  {}) is rw = 0;
    has Numeric $.HorizScaling  is graphics(method ($!HorizScaling) {}) is rw = 100;
    has Numeric $.TextLeading   is graphics(method ($!TextLeading)  {}) is rw = 0;
    has Numeric $.TextRender    is graphics(method ($!TextRender)   {}) is rw = 0;
    has Numeric $.TextRise      is graphics(method ($!TextRise)     {}) is rw = 0;
    has Numeric @.TextMatrix    is graphics(method (*@!TextMatrix)  {}) is rw = [ 1, 0, 0, 1, 0, 0, ];
    has Array   $.Font          is graphics(method (Str $key, Numeric $size!) {
        with self.parent {
            with .resource-entry('Font', $key) -> \font-face {
                $!Font = [font-face, $size];
            }
            else {
                die X::PDF::Content::UnknownResource.new: :type<Font>, :$key;
            }
        }
        else {
            $!Font = [$key, $size];
        }
    }) is rw;
    method font-face {$!Font[0]}
    method font-size {$!Font[1]}

    # *** Graphics STATE ***
    has Numeric @.CTM is graphics = [ 1, 0, 0, 1, 0, 0, ];      # graphics matrix;
    method CTM is rw {
        Proxy.new(
            FETCH => sub ($) {@!CTM},
            STORE => sub ($, List $gm) {
                my @ctm-inv = inverse(@!CTM);
                my @diff = multiply($gm, @ctm-inv);
                self.ConcatMatrix( |@diff )
                    unless is-identity(@diff);
                @!CTM;
            });
    }
    has Numeric $.LineWidth   is graphics(method ($!LineWidth) {}) is rw = 1.0;
    has UInt    $.LineCap     is graphics(method ($!LineCap) {}) is rw = ButtCaps;
    has UInt    $.LineJoin    is graphics(method ($!LineJoin) {}) is rw = MiterJoin;
    has         @.DashPattern is graphics(method (Array $a, Numeric $p ) {
                                               @!DashPattern = [ $a.clone, $p];
                                           }) is rw = [[], 0];
    my subset ColorSpace of Str where 'DeviceRGB'|'DeviceGray'|'DeviceCMYK'|'DeviceN'|'Pattern'|'Separation'|'ICCBased'|'Indexed'|'Lab'|'CalGray'|'CalRGB';

    has Str $.StrokeColorSpace is graphics(method ($!StrokeColorSpace) {}) is rw = 'DeviceGray';
    has @!StrokeColor is graphics = [0.0];
    method StrokeColor is rw {
        Proxy.new(
            FETCH => sub ($) {$!StrokeColorSpace => @!StrokeColor},
            STORE => sub ($, Pair $_) {
                my Str $key = .key ~~ Str ?? .key !! $.resource-key(.key);
                unless $key eq $!StrokeColorSpace && .value eqv @!StrokeColor {
                    if $key ~~ /^ Device(RGB|Gray|CMYK) $/ {
                        my Str $cs = ~ $0;
                        self."SetStroke$cs"(|.value);
                    }
                    else {
                        self.SetStrokeColorSpace($key);
                        self.SetStrokeColorN(|.value);
                    }
                }
            }
        );
    }

    has Str $.FillColorSpace is graphics(method ($!FillColorSpace) { }) is rw = 'DeviceGray';
    has @!FillColor is graphics = [0.0];
    method FillColor is rw {
        Proxy.new(
            FETCH => sub ($) {$!FillColorSpace => @!FillColor},
            STORE => sub ($, Pair $_) {
                my Str $key = .key ~~ Str ?? .key !! $.resource-key(.key);
                unless $key eq $!FillColorSpace && .value eqv @!FillColor {
                    if $key ~~ /^ Device(RGB|Gray|CMYK) $/ {
                        my Str $cs = ~ $0;
                        self."SetFill$cs"(|.value);
                    }
                    else {
                        self.SetFillColorSpace($key);
                        self.SetFillColorN(|.value);
                    }
                }
            }
        );
    }

    my subset RenderingIntention of Str where 'AbsoluteColorimetric'|'RelativeColorimetric'|'Saturation'|'Perceptual';
    has RenderingIntention $.RenderingIntent is graphics(method ($!RenderingIntent)  {}) is rw = 'RelativeColorimetric';

    my subset FlatnessTolerance of Numeric where 0 .. 100;
    has FlatnessTolerance $.Flatness is graphics(method ($!Flatness)  {}) is rw = 0;

    # *** Extended Graphics STATE ***
    has $.StrokeAlpha is ext-graphics is rw = 1.0;
    has $.FillAlpha   is ext-graphics is rw = 1.0;

    has @.gsave;
    has PDF::Content::Tag @.open-tags;
    has PDF::Content::Tag @.tags;
    multi method tags(@tags = @!tags, :$flat! where .so) {
        flat @tags.map: {
            ($_,
             self.tags(.children.grep(PDF::Content::Tag), :flat))
        }
    }
    multi method tags is rw is default { @!tags }

    # *** Type 3 Font Metrics ***

    has Numeric $.char-width;
    has Numeric $.char-height;
    has Numeric @.char-bbox[4];

    # States and transitions in [PDF 32000 Figure 9 – Graphics Objects]
    my enum GraphicsContext is export(:GraphicsContext) <Path Text Clipping Page Shading Image>;

    has GraphicsContext $.context = Page;

    method !track-context(Str $op) {

        my constant %Transition = %(
            'BT'     => ( (Page) => Text ),
            'ET'     => ( (Text) => Page ),

            'BI'     => ( (Page) => Image ),
            'EI'     => ( (Image) => Page ),

            'W'|'W*' => ( (Path) => Clipping ),
            'm'|'re' => ( (Page) => Path ),
            'Do'     => ( (Page) => Page ),
            any(PaintingOps.keys) => ( (Clipping|Path) => Page ),
        );

        my constant %InSitu = %(
           (Path) => PathOps ∪ CompatOps,
           (Text) => TextOps ∪ TextStateOps ∪ GeneralGraphicOps ∪ ColorOps ∪ MarkedContentOps ∪ CompatOps,
           (Page) => TextStateOps ∪ SpecialGraphicOps ∪ GeneralGraphicOps ∪ ColorOps ∪ MarkedContentOps ∪ CompatOps ∪ FontOps ∪ <sh>.Set,
           (Image) => <ID>.Set,
        );

        my Bool $ok-here = False;
        my $prev-context = $!context;
        $ok-here = $op ∈ $_
            with %InSitu{$!context};

        with %Transition{$op} {
            $ok-here ||= ?(.key == $!context);
            $!context = .value;
        }

        if !$ok-here && $!strict {
            # Found an op we didn't expect. Raise a warning.
            my $type;
            my $where;
            if $!context == Text && $op ∈ SpecialGraphicOps {
                $type = 'special graphics';
                $where = 'in a BT ... ET text block';
            }
            elsif $op ∈ TextOps {
                $type = 'text operation';
                $where = 'outside of a BT ... ET text block';
            }
            else {
                $type = 'unexpected';
                $where = '(first operation)';

                loop (my int $n = +@!ops-2; $n >= 0; $n--) {
                    with @!ops[$n].key {
                        unless $_ ~~ 'comment' {
                            $where = "in $prev-context context, following '$_' (%OpName{$_})";
                            last;
                        }
                    }
                }
            }
            warn X::PDF::Content::OP::Unexpected.new: :$type, :$op, :mnemonic(%OpName{$op}), :$where;
        }
    }

    my Routine %Ops = BEGIN %(

        # BI dict ID stream EI
        'BI' => sub (Str, Hash $dict = {}) {
            [ :$dict ];
        },

        'ID' => sub (Str, Str $encoded = '') {
            [ :$encoded ];
        },

        'EI' => sub ($op) { $op => [] },

        # unary operators
        'BT'|'ET'|'EMC'|'BX'|'EX'|'b*'|'b'|'B*'|'B'|'f*'|'F'|'f'
            |'h'|'n'|'q'|'Q'|'s'|'S'|'T*'|'W*'|'W' => sub ($op) {
            [];
        },

        # tag                     BMC | MP
        # name                    cs | CS | Do | sh
        # dictname                gs
        # intent                  ri
        'BMC'|'cs'|'CS'|'Do'|'gs'|'MP'|'ri'|'sh' => sub (Str, Str $name!) {
            [ :$name ]
        },

        # string                  Tj | '
        'Tj'|"'" => sub (Str, Str $literal!) {
            [ :$literal ]
         },

        # array                   TJ
        'TJ' => sub (Str $op, Array $args!) {
            my @array = $args.map({
                when Str     { :literal($_) }
                when Numeric { :int(.Int) }
                when Pair    { $_ }
                default {die X::PDF::Content::OP::BadArrayArg.new: :$op, :mnemonic(%OpName{$op}), :arg($_);}
            });
            [ :@array ];
        },

        # name num                Tf
        'Tf' => sub (Str, Str $name!, Numeric $real!) {
            [ :$name, :$real ]
        },

        # tag [dict|name]         BDC | DP
        'BDC'|'DP' => sub (Str, Str $name!, $p! where Hash|Str|Pair) {
            my Pair $prop = do given $p {
                when Hash { PDF::COS.coerce(:dict($p)).content }
                when Str  { :name($p) }
            }
            [ :$name, $prop ]
        },

        # dashArray dashPhase    d
        'd' => sub (Str $op, List $args!, Numeric $real!) {
            my @array = $args.map({
                when Numeric { :real($_) }
                when Pair    { $_ }
                default {die X::PDF::Content::OP::BadArg.new: :$op, :mnemonic(%OpName{$op}), :arg($_) }
            });
            [ :@array, :$real ];
        },

        # flatness               i
        # gray                   g | G
        # miterLimit             m
        # charSpace              Tc
        # leading                TL
        # rise                   Ts
        # wordSpace              Tw
        # scale                  Tz
        # lineWidth              w
        'i'|'g'|'G'|'M'|'Tc'|'TL'|'Ts'|'Tw'|'Tz'|'w' => sub (Str, Numeric $real!) {
            [ :$real ]
        },

        # lineCap                J
        # lineJoin               j
        # render                 Tr
        'j'|'J'|'Tr' => sub (Str, UInt $int!) {
            [ :$int ]
        },

        # x y                    m l
        # wx wy                  d0
        # tx ty                  Td TD
        'd0'|'l'|'m'|'Td'|'TD' => sub (Str, Numeric $n1!, Numeric $n2!) {
            [ :real($n1), :real($n2) ]
        },

        # aw ac string           "
        '"' => sub (Str, Numeric $n1!, Numeric $n2!, Str $literal! ) {
            [ :real($n1), :real($n2), :$literal ]
        },

        # r g b                  rg | RG
        'rg'|'RG' => sub (Str, Numeric $n1!,
                          Numeric $n2!, Numeric $n3!) {
            [ :real($n1), :real($n2), :real($n3) ]
        },

        # c m y k                k | K
        # x y width height       re
        # x2 y2 x3 y3            v y
        'k'|'K'|'re'|'v'|'y' => sub (Str, Numeric $n1!, Numeric $n2!,
                                          Numeric $n3!, Numeric $n4!) {
            [ :real($n1), :real($n2), :real($n3), :real($n4) ]
        },

        # x1 y1 x2 y2 x3 y3      c | cm
        # wx wy llx lly urx ury  d1
        # a b c d e f            Tm
        'c'|'cm'|'d1'|'Tm' => sub (Str,
            Numeric $n1!, Numeric $n2!, Numeric $n3!, Numeric $n4!, Numeric $n5!, Numeric $n6!) {
            [ :real($n1), :real($n2), :real($n3), :real($n4), :real($n5), :real($n6) ]
        },

        # c1, ..., cn             sc | SC
        'sc'|'SC' => sub (Str $op, *@args is copy) {

            die X::PDF::Content::OP::TooFewArgs.new: :$op, :mnemonic(%OpName{$op})
                unless @args;

            @args = @args.map: {
                when Pair    {$_}
                when Numeric { :real($_) }
                default {
                    die X::PDF::Content::OP::BadArg.new: :$op, :mnemonic(%OpName{$op}), :arg($_);
                }
            };

            @args
        },

        # c1, ..., cn [name]      scn | SCN
        'scn'|'SCN' => sub (Str $op, *@_args) {

            my @args = @_args.list;
            die X::PDF::Content::OP::TooFewArgs.new: :$op, :mnemonic(%OpName{$op})
                unless @args;

            # scn & SCN have an optional trailing name
            my Str $name = @args.pop
                if @args.tail ~~ Str;

            @args = @args.map: {
                when Pair    {$_}
                when Numeric { :real($_) }
                default {
                    die X::PDF::Content::OP::BadArrayArg.new: :$op, :mnemonic(%OpName{$op}), :arg($_);
                }
            };

            @args.push: (:$name) if $name.defined;

            @args
        },
     );

    proto sub op(|c) returns Pair {*}
    # semi-raw and a little dwimmy e.g:  op('TJ' => [[:literal<a>, :hex-string<b>, 'c']])
    #                                     --> :TJ( :array[ :literal<a>, :hex-string<b>, :literal<c> ] )
    my subset Comment of Pair where {.key eq 'comment'}
    multi sub op(Comment $comment!) { $comment }
    multi sub op(Pair $raw!) {
        my Str $op = $raw.key;
        my @raw-vals = $raw.value.grep(* !~~ Comment);
        # validate the operation and get fallback coercements for any missing pairs
        my @vals = @raw-vals.map: { from-ast($_) };
        my \opn = op($op, |@vals);
	my \coerced-vals = opn.value;

	my @ast-values = @raw-vals.pairs.map({
	    .value ~~ Pair
		?? .value
		!! coerced-vals[.key]
	});
	$op => [ @ast-values ];
    }

    multi sub op(Str $op, |c) is default {
        with %Ops{$op} {
            CATCH {
                when X::PDF::Content {.rethrow }
                default {
                    die X::PDF::Content::OP::Error.new: :$op, :mnemonic(%OpName{$op}), :error($_);
                }
            }
            $op => .($op,|c);
        }
        else {
            die X::PDF::Content::OP::Unknown.new :$op;
        }
    }

    method is-graphics-op($op-name) {
        my constant GraphicsOps = GeneralGraphicOps ∪ ColorOps ∪ set <cm>;
        $op-name ∈ GraphicsOps;
    }

    multi method op(Comment $_) { $_ }
    multi method op(*@args is copy) {
        $!content-cache = Nil;
        my \opn = op(|@args);
	my Str $op = do given opn {
            when Pair {
                @args = .value.map: *.value;
                .key.Str
            }
            default {
                .Str;
            }
        }

        if $!strict && !@!gsave && self.is-graphics-op($op) {
            # not illegal just bad practice to perform graphics outside of a
            # block. makes it harder to later edit/reuse this content stream
            # and may upset downstream utilities
            warn X::PDF::Content::OP::Unexpected.new: :$op, :mnemonic(%OpName{$op}), :type('graphics operator'), :where("outside of a 'q' ... 'Q' (Save .. Restore) graphics block");
	}

	@!ops.push(opn);
        unless $op ~~ Comment {

            if $op ~~ 'BDC'|'DP'|'TJ'|'d' {
                # operation may have array or dict operands
                @args = @args.map: {
                    when List { [ .map: *.value ] }
                    when Hash { %( .map: {.key => .value.value} ) }
                    default { $_ }
                }
            }

            # built-in callbacks
            self!track-context($op);
            self.track-graphics($op, |@args );

            # user supplied callbacks
	    if @!callback {
                my $*gfx = self;
                .($op, |@args )
                    for @!callback;
            }
            opn.value.push: (:comment(%OpName{$op}))
                if $!comment-ops && $op ne 'ID';
        }
	opn;
    }

    multi method ops(Str $ops!) {
	$.ops( self.parse($ops) );
    }

    multi method ops(List $ops?) {
	with $ops {
	    self.op($_)
		for .list
	}
        @!ops;
    }

    method add-comment(Str $_) {
        @!ops.push: (:comment[$_]);
    }

    method parse(Str $content) {
	use PDF::Grammar::Content::Fast;
	use PDF::Grammar::Content::Actions;
	state $actions = PDF::Grammar::Content::Actions.new: :strict;
	my \p = PDF::Grammar::Content::Fast.parse($content, :$actions)
	    // die X::PDF::Content::ParseError.new :$content;
	p.ast
    }

    multi method track-graphics('q') {

        my %gstate = %GraphicVars.pairs.map: {
            my Str $key       = .key;
            my Attribute $att = .value;
            my $val           = $att.get_value(self);
            $val .= clone if $val ~~ Array;
            $key => $val;
        }

        @!gsave.push: %gstate;
    }

    multi method track-graphics('Q') {
        die X::PDF::Content::OP::BadNesting.new: :op<Q>, :mnemonic(%OpName<Q>), :opener("'q' (%OpName<q>)")
            unless @!gsave;

        my %gstate = @!gsave.pop;

        for %gstate.pairs {
            my Str $key       = .key;
            my Attribute $att = %GraphicVars{$key};
            my $val           = .value;
            $att.set_value(self, $val);
        }
    }

    multi method track-graphics('BT') {
        @!TextMatrix = [ 1, 0, 0, 1, 0, 0, ];
    }

    multi method track-graphics('ET') {
        @!TextMatrix = [ 1, 0, 0, 1, 0, 0, ];
    }

    multi method track-graphics('cm', \a, \b, \c, \d, \e, \f) {
        @!CTM = multiply([a, b, c, d, e, f], @!CTM);
    }

    multi method track-graphics('rg', \r, \g, \b) {
        $!FillColorSpace = 'DeviceRGB';
        @!FillColor = [r, g, b];
    }

    multi method track-graphics('RG', \r, \g, \b) {
        $!StrokeColorSpace = 'DeviceRGB';
        @!StrokeColor = [r, g, b]
    }

    multi method track-graphics('g', \gray) {
        $!FillColorSpace = 'DeviceGray';
        @!FillColor = [ gray, ];
    }

    multi method track-graphics('G', \gray) {
        $!StrokeColorSpace = 'DeviceGray';
        @!StrokeColor = [ gray, ];
    }

    multi method track-graphics('k', \c, \m, \y, \k) {
        $!FillColorSpace = 'DeviceCMYK';
        @!FillColor = [ c, m, y, k ];
    }

    multi method track-graphics('K', \c, \m, \y, \k) {
        $!StrokeColorSpace = 'DeviceCMYK';
        @!StrokeColor = [ c, m, y, k ];
    }

    method !color-args-ok($op, @colors) {
        my Str $cs = do given $op {
            when 'SC'|'SCN' {$!StrokeColorSpace}
            when 'sc'|'scn' {$!FillColorSpace}
        }

        constant %Arity = %(
            'DeviceGray'|'CalGray'|'Indexed' => 1,
            'DeviceRGB'|'CalRGB'|'Lab' => 3,
            'DeviceCMYK' => 4
        );

        with %Arity{$cs} -> \arity {
            my $got = +@colors;
            $got-- if $op.uc eq 'SCN' && @colors.tail ~~ Str;
            die X::PDF::Content::OP::ArgCount.new: :message("Incorrect number of arguments in $op command, expected {arity} $cs colors, got: $got")
                unless $got == arity;
        }
        True;
    }

    multi method track-graphics('scn', *@colors where self!color-args-ok('scn', @colors)) {
        @!FillColor = @colors;
    }

    multi method track-graphics('SCN', *@colors where self!color-args-ok('SCN', @colors)) {
        @!StrokeColor = @colors;
    }

    multi method track-graphics('sc',  *@colors where self!color-args-ok('sc',  @colors)) {
        @!FillColor = @colors;
    }

    multi method track-graphics('SC',  *@colors where self!color-args-ok('SC',  @colors)) {
        @!StrokeColor = @colors;
    }

    method !open-tag(PDF::Content::Tag $tag) {
        $tag.start = +@!ops;
        with @!open-tags.tail {
            .add-kid: $tag;
        }
        @!open-tags.push: $tag;
    }

    method !close-tag {
	my PDF::Content::Tag $tag = @!open-tags.pop;
        $tag.end = +@!ops;
        @!tags.push: $tag
            without $tag.parent;
    }

    method !add-tag(PDF::Content::Tag $tag) {
        $tag.start = $tag.end = +@!ops;
        with @!open-tags.tail {
            .add-kid: $tag;
        }
        else {
            @!tags.push: $tag
        }
    }

    multi method track-graphics('BMC', Str $name!) {
        self!open-tag: PDF::Content::Tag.new: :op<BMC>, :$name;
    }

    multi method track-graphics('BDC', Str $name, $p where Str|Hash) {
        my $props = $p ~~ Str ?? $.resource-entry('Properties', $p) !! $p;
        self!open-tag: PDF::Content::Tag.new: :op<BDC>, :$name, :$props;
    }

    multi method track-graphics('EMC') {
	die X::PDF::Content::OP::BadNesting.new: :op<EMC>, :mnemonic(%OpName<EMC>), :opener("'BMC' or 'BDC' (BeginMarkedContent)")
	    unless @!open-tags;
        self!close-tag;
    }

    multi method track-graphics('MP', Str $name!) {
        self!add-tag: PDF::Content::Tag.new: :op<MP>, :$name;
    }

    multi method track-graphics('DP', Str $name!, $p where Str|Hash) {
        my $props = $p ~~ Str ?? $.resource-entry('Properties', $p) !! $p;
        self!add-tag: PDF::Content::Tag.new: :op<DP>, :$name, :$props;
    }

    multi method track-graphics('Do', Str $name!) {
        self!add-tag: PDF::Content::Tag.new: :op<Do>, :$name;
    }

    multi method track-graphics('gs', Str $key) {
        with self.parent {
            with .resource-entry('ExtGState', $key) {
                with .<CA>   { $!StrokeAlpha = $_ }
                with .<ca>   { $!FillAlpha = $_ }
                with .<D>    { @!DashPattern = .list }
                with .<Font> { $!Font = $_ }
                with .<FT>   { $!Flatness = $_ }
                with .<LC>   { $!LineCap = $_ }
                with .<LJ>   { $!LineJoin = $_ }
                with .<LW>   { $!LineWidth = $_ }
                with .<RI>   { $!RenderingIntent = $_ }
            }
            else {
                die X::PDF::Content::UnknownResource.new: :type<ExtGState>, :$key;
            }
        }
    }

    method !text-move(Numeric $tx, Numeric $ty) {
        @!TextMatrix = multiply([1, 0, 0, 1, $tx, $ty], @!TextMatrix);
    }

    method !new-line {
        self!text-move(0, - $!TextLeading);
    }

    multi method track-graphics('Td', Numeric $tx!, Numeric $ty) {
        self!text-move($tx, $ty);
    }

    multi method track-graphics('TD', Numeric $tx!, Numeric $ty) {
        $!TextLeading = - $ty;
        self!text-move($tx, $ty);
    }

    multi method track-graphics('T*') {
        self!new-line();
    }

    multi method track-graphics("'", $) {
        self!new-line();
    }

    multi method track-graphics('"', $!WordSpacing, $!CharSpacing, $) {
        self!new-line();
    }

    multi method track-graphics('d0', $!char-width, $!char-height) {
    }

    multi method track-graphics('d1', $!char-width, $!char-height, *@!char-bbox) {
    }

    multi method track-graphics($op, *@args) is default {
        .(self,|@args) with %PostOp{$op};
    }

    method finish {
	die X::PDF::Content::Unclosed.new: :message("Unclosed tags {@!open-tags.map(*.gist).join: ' '} at end of content stream")
	    if @!open-tags;
	die X::PDF::Content::Unclosed.new: :message("'q' (Save) unmatched by closing 'Q' (Restore) at end of content stream")
	    if @!gsave;
        warn X::PDF::Content::Unclosed.new: :message("unexpected end of content stream in $!context context")
            if $!strict && $!context != Page;

        with $!parent {
            try .cb-finish for .resources('Font').values;
        }
    }

    #| serialize content into a string. indent blocks for readability
    has Str $!content-cache;
    method Str { $!content-cache //= self!content }
    method !content returns Str {
	my constant Openers = 'q'|'BT'|'BMC'|'BDC'|'BX';
	my constant Closers = 'Q'|'ET'|'EMC'|'EX';
        my PDF::Writer $writer .= new;

	$.finish;
	my UInt $nesting = 0;

        @!ops.map({
	    my \op = ~ .key;

	    $nesting-- if $nesting && op ~~ Closers;
	    $writer.indent = '  ' x $nesting;
	    $nesting++ if op ~~ Openers;

	    my \pad = op eq 'EI'
                ?? ''
                !! $writer.indent;
            pad ~ $writer.write: :content($_);
	}).join: "\n";
    }

    # serialized current content as an array of strings - for debugging/testing
    method content-dump {
        my PDF::Writer $writer .= new;

        @!ops.map: {
	    $writer.write: :content($_);
	};
    }

    method dispatch:<.?>(\name, |c) is raw {
        self.can(name) || OpCode.enums{name} ?? self."{name}"(|c) !! Nil
    }
    method ShowSpaceText(Array $args) {
        self.op(OpCode::ShowSpaceText, $args);
    }
    method FALLBACK(\name, |c) {
        with OpCode.enums{name} -> \op {
            # e.g. $.Restore :== $.op('Q', [])
            self.op(op, |c);
        }
        else {
            die X::Method::NotFound.new( :method(name), :typename(self.^name) );
        }
    }
}

=begin pod

=head1 NAME

PDF::Content::Ops

=head1 DESCRIPTION

The PDF::Content::Ops role implements methods and mnemonics for the full operator table, as defined in specification [PDF 1.7 Appendix A]:

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
BX | BeginExtended | — | (PDF 1.1) Begin compatibility section
c | CurveTo | x1 y1 x2 y2 x3 y3 | Append curved segment to path (two control points)
cm | ConcatMatrix | a b c d e f | Concatenate matrix to current transformation matrix
CS | SetStrokeColorSpace | name | (PDF 1.1) Set color space for stroking operations
cs | SetFillColorSpace | name | (PDF 1.1) Set color space for nonstroking operations
d | SetDashPattern | dashArray dashPhase | Set line dash pattern
d0 | SetCharWidth | wx wy | Set glyph width in Type 3 font
d1 | SetCharWidthBBox | wx wy llx lly urx ury | Set glyph width and bounding box in Type 3 font
Do | XObject | name | Invoke named XObject
DP | MarkPointDict | tag properties | (PDF 1.2) Define marked-content point with property list
EI | EndImage | — | End inline image object
EMC | EndMarkedContent | — | (PDF 1.2) End marked-content sequence
ET | EndText | — | End text object
EX | EndExtended | — | (PDF 1.1) End compatibility section
f | Fill | — | Fill path using nonzero winding number rule
F | FillObsolete | — | Fill path using nonzero winding number rule (obsolete)
f* | EOFill | — | Fill path using even-odd rule
G | SetStrokeGray | gray | Set gray level for stroking operations
g | SetFillGray | gray | Set gray level for nonstroking operations
gs | SetGraphicsState | dictName | (PDF 1.2) Set parameters from graphics state parameter dictionary
h | ClosePath | — | Close subpath
i | SetFlatness | flatness | Set flatness tolerance
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
