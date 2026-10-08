/* =========================================================================================

   This is an auto-generated file: Any edits you make may be overwritten!

*/

#pragma once

namespace BinaryData
{
    extern const char*   verticalKnob_svg;
    const int            verticalKnob_svgSize = 58206;

    extern const char*   horizontalKnob_svg;
    const int            horizontalKnob_svgSize = 60770;

    extern const char*   irsOrd1_wav;
    const int            irsOrd1_wavSize = 1932;

    extern const char*   irsOrd2_wav;
    const int            irsOrd2_wavSize = 4292;

    extern const char*   irsOrd3_wav;
    const int            irsOrd3_wavSize = 7596;

    extern const char*   irsOrd4_wav;
    const int            irsOrd4_wavSize = 11844;

    extern const char*   irsOrd5_wav;
    const int            irsOrd5_wavSize = 17036;

    extern const char*   irsOrd6_wav;
    const int            irsOrd6_wavSize = 23172;

    extern const char*   irsOrd7_wav;
    const int            irsOrd7_wavSize = 30252;

    // Number of elements in the namedResourceList and originalFileNames arrays.
    const int namedResourceListSize = 9;

    // Points to the start of a list of resource names.
    extern const char* namedResourceList[];

    // Points to the start of a list of resource filenames.
    extern const char* originalFilenames[];

    // If you provide the name of one of the binary resource variables above, this function will
    // return the corresponding data and its size (or a null pointer if the name isn't found).
    const char* getNamedResource (const char* resourceNameUTF8, int& dataSizeInBytes);

    // If you provide the name of one of the binary resource variables above, this function will
    // return the corresponding original, non-mangled filename (or a null pointer if the name isn't found).
    const char* getNamedResourceOriginalFilename (const char* resourceNameUTF8);
}
