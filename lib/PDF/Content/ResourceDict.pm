use v6;

role PDF::Content::ResourceDict {

    use PDF::COS;
    use PDF::COS::Name;
    use PDF::Content::Font;

    has Str %!resource-key; # {Any}
    has Int %!counter;

    method resource-key($object, |c --> Str:D) {
        self!register-resource($object, |c)
            unless %!resource-key{$object.WHICH}:exists;
       %!resource-key{$object.WHICH};
    }

    method !resource-type( PDF::COS $_ ) {
        when Hash {
            when .<Type> ~~ 'ExtGState'|'Font'|'XObject'|'Pattern' {
                .<Type>
            }
            when .<Subtype> ~~ 'Form'|'Image'|'PS' {
                # XObject with /Type defaulted
                'XObject'
            }
            when .<PatternType>:exists { 'Pattern' }
            when .<ShadingType>:exists { 'Shading' }
            default { 'Other' }
        }
        when List && .[0] ~~ PDF::COS::Name {
            # e.g. [ /CalRGB << /WhitePoint [ 1.0 1.0 1.0 ] >> ]
            'ColorSpace'
        }
        default {
	    warn "unrecognised graphics resource object: {.perl}";
	    'Other'
        }
    }

    method find-resource( &match, Str :$type! ) {
        my $entry;

        with self{$type} -> $resources {

            for $resources.keys {
                my $resource = $resources{$_};
                if match($resource) {
		    $entry = $resource;
		    %!resource-key{$entry.WHICH} = $_;
                    last;
                }
            }
        }

        $entry;
    }

    #| ensure that the object is registered as a page resource. Return a unique
    #| name for it.
    method !register-resource(PDF::COS $object,
                             Str :$type = self!resource-type($object),
	) {

	my constant %Prefix = %(
	    :ColorSpace<CS>, :Font<F>, :ExtGState<GS>, :Pattern<Pt>,
            :Shading<Sh>, :XObject{  :Form<Fm>, :Image<Im>, :PS<PS> },
	    :Other<Obj>,
	);

	my $prefix = $type eq 'XObject'
	    ?? %Prefix{$type}{ $object<Subtype> }
	    !! %Prefix{$type};

        my Str $key;
        # make a unique resource key
        repeat {
            $key = $prefix ~ ++%!counter{$prefix};
        } while self.keys.first: { self{$_}{$key}:exists };

        self{$type}{$key} = $object;

	%!resource-key{$object.WHICH} = $key;
        $object;
    }

    multi method resource($object where { %!resource-key{.WHICH}:exists }) {
	$object;
    }

    multi method resource(PDF::COS $object, Bool :$eqv=False ) is default {
        my Str $type = self!resource-type($object)
            // die "not a resource object: {$object.WHAT}";

	my &match = $eqv
	    ?? sub ($_){$_ eqv $object}
	    !! sub ($_){$_ === $object};
        self.find-resource(&match, :$type)
            // self!register-resource( $object );
    }

    method resource-entry(Str:D $type!, Str:D $key!) {
        .{$key} with self{$type};
    }

    method core-font(|c) {
        self.use-font: (require ::('PDF::Content::Font::CoreFont')).load-font( |c );
    }

    multi method use-font(PDF::Content::Font $font) {
        my $font-obj = $font.font-obj;
        self.find-resource(sub ($_){ .?font-obj === $font-obj },
			   :type<Font>)
            // self!register-resource( $font );
    }

    multi method use-font($font-obj) is default {
        self.find-resource(sub ($_){ .?font-obj === $font-obj },
			   :type<Font>)
            // self!register-resource: $font-obj.to-dict;
    }

}
