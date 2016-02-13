use v6;
use Test;
use PDF::Grammar::Test :is-json-equiv;

use PDF::Graphics::Image;

my $jpeg;
lives-ok {$jpeg = PDF::Graphics::Image.open: "t/images/jpeg.jpg";}, "open jpeg - lives";
isa-ok $jpeg, ::('PDF::DAO::Stream'), 'jpeg object';
is $jpeg<Type>, 'XObject', 'jpeg type';
is $jpeg<Subtype>, 'Image', 'jpeg subtype';
is $jpeg<Width>, 24, 'jpeg width';
is $jpeg<Height>, 24, 'jpeg height';
is $jpeg<BitsPerComponent>, 8, 'jpeg bpc';
is $jpeg<ColorSpace>, 'DeviceRGB', 'jpeg cs';
ok $jpeg<Length>, 'jpeg dict length';
is $jpeg.encoded.codes, $jpeg<Length>, 'jpeg encoded length';

my $gif;
lives-ok {$gif = PDF::Graphics::Image.open: "t/images/lightbulb.gif";}, "open gif - lives";
isa-ok $gif, ::('PDF::DAO::Stream'), 'gif object';
is $gif<Type>, 'XObject', 'gif type';
is $gif<Subtype>, 'Image', 'gif subtype';
is $gif<Width>, 19, 'gif width';
is $gif<Height>, 19, 'gif height';
is $gif<BitsPerComponent>, 8, 'gif bpc';
is-json-equiv $gif<ColorSpace>, ['Indexed', 'DeviceRGB', 31, "\xFF\xFF\xFF\xFF\xFB\xF0\xFF\xDF\xFF\xD4\xDF\xFF\xCC\xCC\xFF\xC0\xDC\xC0\xA6\xCA\xF0\xFF\x98\xFF\xFF\xFF\xAA\xFF\xDF\xAA\xD4\xDF\xAA\xD4\xBF\xAA\xD4\x9F\xAA\xAA\xBF\xAA\xA0\xA0\xA4\xAA\x9F\xAA\x80\x80\x80\x7F\x9F\xAA\xFF\xFF\x55\xFF\xDF\x55\xD4\xBF\x55\xD4\x9F\x55\xAA\x9F\x55\x80\x80\x00\xAA\x7F\x55\xAA\x5F\x55\xAA\x7F\x00\x7F\x5F\x55\x55\x5F\x55\x2A\x5F\x55\x55\x3F\x55\x00\x00\x00" ], 'gif cs';
ok $gif<Length>, 'gif dict length';
is $gif.encoded.codes, $gif<Length>, 'gif encoded length';

for (
    'png-1bit-gray' => {
        :file<t/images/basn0g01.png>, :Width(32), :Height(32),
        :Filter<FlateDecode>, :ColorSpace<DeviceGray>, :BitsPerComponent(1),
        :Colors(1), :Columns(32), :Predictor(15), },
    'png-8bit-rgb' => {
        :file<t/images/basn2c08.png>, :Width(32), :Height(32),
        :Filter<FlateDecode>, :ColorSpace<DeviceRGB>, :BitsPerComponent(8),
        :Colors(3), :Columns(32), :Predictor(15), },
    'png-16bit-rgb' => {
        :file<t/images/basn2c16.png>, :Width(32), :Height(32),
        :Filter<FlateDecode>, :ColorSpace<DeviceRGB>, :BitsPerComponent(16),
        :Colors(3), :Columns(32), :Predictor(15), },
    )  {
    my $desc = .key;
    my $test = .value;

    my $png;
    lives-ok {$png = PDF::Graphics::Image.open: $test<file>;}, "open $desc - lives";
    isa-ok $png, ::('PDF::DAO::Stream'), "$desc object";
    is $png<Type>, 'XObject', "$desc type";
    is $png<Subtype>, 'Image', "$desc subtype";
    is $png<Width>, $test<Width>, "$desc width";
    is $png<Height>,$test<Height>, "$desc height";
    is $png<Filter>, $test<Filter>, "$desc filter";
    is $png<ColorSpace>, $test<ColorSpace>, "$desc color-space";

    my $decode = $png<DecodeParms>;
    is $decode<BitsPerComponent>, $test<BitsPerComponent>, "$desc decode bpc";
    is $decode<Colors>, $test<Colors>, "$desc decode colors";
    is $decode<Columns>,$test<Columns>, "$desc decode columns";
    is $decode<Predictor>, $test<Predictor>, "$desc decode predictor";

    ok $png<Length>, "$desc dict length";
    is $png.encoded.codes, $png<Length>, "$desc encoded length";
}

done-testing;