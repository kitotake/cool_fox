//! The `WAVE64-*` diagnostic lines (their shader label), the per-program switch for wave-wide
//! branches (`VICTORY_WAVE_WIDE_ALLOW`) and the error of a wave64 compute program that stays
//! a program of 64 lanes on a host of 32 (listed apart when its thread group is several
//! console waves).

use super::{
    NO_WAVE32, NO_WAVE32_SEVERAL_WAVES, diag_line, digest_hex, no_wave32_lowering, wide_allowed,
    with_diag_label,
};
use crate::ShaderError;
use crate::native::{ComputeIo, HwStage, NativeProgram, StageIo};

/// A compute program of a thread group of `threads` x 1 x 1 (no code: only its group is read).
fn group_of(threads: [u32; 3], wave64: bool) -> NativeProgram {
    NativeProgram {
        stage: HwStage::Cs,
        wave64,
        vgprs: 1,
        layout: vec![],
        used: vec![],
        io: StageIo::Cs(ComputeIo { rsrc2: 0, threads }),
        code: vec![],
    }
}

fn what(e: ShaderError) -> &'static str {
    match e {
        ShaderError::Unsupported { what, offset: 0 } => what,
        other => panic!("not the error of a program kept at 64 lanes: {other:?}"),
    }
}

#[test]
fn a_diagnostic_line_without_a_label_is_what_it_always_was() {
    assert_eq!(
        diag_line("WAVE64-RETRY", format_args!("local waves: wave {:?}", Some(64))),
        "WAVE64-RETRY local waves: wave Some(64)"
    );
    assert_eq!(
        diag_line("WAVE64-WHY", format_args!("group={} lds={} [{}]", 128, true, "v_mbcnt")),
        "WAVE64-WHY group=128 lds=true [v_mbcnt]"
    );
}

#[test]
fn a_label_goes_in_brackets_after_the_tag_and_ends_with_the_closure() {
    let inside = with_diag_label("water_shading:CS_X #5dc3b25986622949", || {
        diag_line("WAVE64-WIDE", format_args!("not tried: thread groups of {:?}", [128, 1, 1]))
    });
    assert_eq!(
        inside,
        "WAVE64-WIDE [water_shading:CS_X #5dc3b25986622949] not tried: thread groups of [128, 1, 1]"
    );
    // (the line's tag stays its first word, for a search on it)
    assert!(inside.starts_with("WAVE64-WIDE "));
    assert_eq!(diag_line("WAVE64-ID", format_args!("x")), "WAVE64-ID x");
}

#[test]
fn nested_labels_give_the_outer_one_back() {
    with_diag_label("outer", || {
        with_diag_label("inner", || assert_eq!(diag_line("T", format_args!("m")), "T [inner] m"));
        assert_eq!(diag_line("T", format_args!("m")), "T [outer] m");
    });
    assert_eq!(diag_line("T", format_args!("m")), "T m");
}

#[test]
fn a_label_is_given_back_when_the_closure_panics() {
    let caught = std::panic::catch_unwind(|| with_diag_label("lost", || panic!("a shader that panics")));
    assert!(caught.is_err());
    assert_eq!(diag_line("T", format_args!("m")), "T m");
}

#[test]
fn a_label_belongs_to_its_thread() {
    with_diag_label("this thread", || {
        let other = std::thread::spawn(|| diag_line("T", format_args!("m"))).join().unwrap();
        assert_eq!(other, "T m");
        assert_eq!(diag_line("T", format_args!("m")), "T [this thread] m");
    });
}

#[test]
fn a_digest_is_named_by_lowercase_hex() {
    let digest = [
        0x58, 0x1d, 0xab, 0x2c, 0xd8, 0xbc, 0xf2, 0x2e, 0x5c, 0x96, 0x4b, 0x98, 0xe9, 0x03, 0x48, 0xd1,
    ];
    assert_eq!(digest_hex(&digest), "581dab2cd8bcf22e5c964b98e90348d1");
}

#[test]
fn wave_wide_allow_names_programs_by_the_start_of_their_digest() {
    let digest = [
        0x58, 0x1d, 0xab, 0x2c, 0xd8, 0xbc, 0xf2, 0x2e, 0x5c, 0x96, 0x4b, 0x98, 0xe9, 0x03, 0x48, 0xd1,
    ];
    // the whole digest, or at least 8 hex digits of its start
    assert!(wide_allowed("581dab2cd8bcf22e5c964b98e90348d1", &digest));
    assert!(wide_allowed("581dab2c", &digest));
    // (any case, spaces around, among others)
    assert!(wide_allowed("00000000, 581DAB2C ,ffffffff", &digest));
    // not a start shorter than 8 digits: it would name programs by chance
    assert!(!wide_allowed("581dab2", &digest));
    assert!(!wide_allowed("5", &digest));
    // not another program, nor the middle of this one's digest, nor nothing at all
    assert!(!wide_allowed("581dab2d", &digest));
    assert!(!wide_allowed("d8bcf22e", &digest));
    assert!(!wide_allowed("", &digest));
    assert!(!wide_allowed(",,", &digest));
    // (a start longer than the digest names nothing)
    assert!(!wide_allowed("581dab2cd8bcf22e5c964b98e90348d100", &digest));
}

#[test]
fn a_wave64_program_of_one_console_wave_or_less_keeps_the_error_it_had() {
    for threads in [[1, 1, 1], [32, 1, 1], [64, 1, 1], [8, 8, 1], [4, 4, 4]] {
        assert_eq!(what(no_wave32_lowering(&group_of(threads, true))), NO_WAVE32, "{threads:?}");
    }
    assert_eq!(NO_WAVE32, "no wave32 lowering for this wave64 program");
}

#[test]
fn a_wave64_program_of_several_console_waves_is_listed_apart() {
    // the groups of the two programs of the 128- and 1024-thread kernels that stay refused
    for threads in [[128, 1, 1], [1024, 1, 1], [65, 1, 1], [16, 16, 1], [8, 8, 8]] {
        assert_eq!(
            what(no_wave32_lowering(&group_of(threads, true))),
            NO_WAVE32_SEVERAL_WAVES,
            "{threads:?}"
        );
    }
    // (the first part of the text stays what a search on the old text finds)
    assert!(NO_WAVE32_SEVERAL_WAVES.starts_with(NO_WAVE32));
    assert_ne!(NO_WAVE32_SEVERAL_WAVES, NO_WAVE32);
}
