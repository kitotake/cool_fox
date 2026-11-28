//! The `WAVE64-*` diagnostic lines (their shader label), the per-program switch for wave-wide
//! branches (`VICTORY_WAVE_WIDE_ALLOW`) and the error of a wave64 compute program that stays
//! a program of 64 lanes on a host of 32 (listed apart when its thread group is several
//! console waves).

use super::{
    NO_WAVE32, NO_WAVE32_SEVERAL_WAVES, diag_line, diag_once_line, digest_hex, lower,
    no_wave32_lowering, wide_allowed, with_diag_label,
};
use crate::native::{
    ComputeIo, HwStage, NativeProgram, ResourceType, RootParam, RootType, StageIo, UsedResource,
};
use crate::{ShaderError, structure};

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

#[test]
fn a_line_is_printed_once_under_a_label_and_every_time_without() {
    let once = |m: &str| diag_once_line("WAVE64-SITE", format_args!("{m}"));
    with_diag_label("shader A", || {
        assert_eq!(once("v_mbcnt x2"), Some("WAVE64-SITE [shader A] v_mbcnt x2".to_owned()));
        assert_eq!(once("v_mbcnt x2"), None);
        assert!(once("v_readlane x1").is_some());
    });
    // another shader names the same sites again
    with_diag_label("shader B", || assert!(once("v_mbcnt x2").is_some()));
    // with no label there is nothing to tell shaders apart by: always printed
    assert!(once("v_mbcnt x2").is_some());
    assert!(once("v_mbcnt x2").is_some());
}

const S_ENDPGM: u32 = 0xBF81_0000;
const DS_WRITE_B32: u8 = 0x0D;
const DS_READ_B32: u8 = 0x36;

/// DS `op vdst, addr, data0` at offset 0.
const fn ds(op: u8, vdst: u8, addr: u8, data0: u8) -> [u32; 2] {
    [0x36 << 26 | (op as u32) << 18, (vdst as u32) << 24 | (data0 as u32) << 8 | addr as u32]
}

/// A wave64 compute program of `threads` threads with 512 bytes of LDS. The threads below s0
/// raise an LDS flag and, in a second branch inside theirs, read it back and write another
/// value (a read and a write in one lane-branch region). `readlane` puts a
/// `v_readlane_b32 s7, v1, 0` in the block every lane runs (`Some(false)`) or in the branch
/// (`Some(true)`).
fn flag_region_program(threads: u32, readlane: Option<bool>, flag_only: bool) -> NativeProgram {
    let mut body = vec![0x7E12_0280]; // v_mov_b32 v9, 0
    if readlane == Some(false) {
        body.extend_from_slice(&[0xD760_0007, 0x0001_0101]);
    }
    body.extend_from_slice(&ds(DS_WRITE_B32, 0, 9, 9));
    let mut branch = vec![0x7E04_0281]; // v_mov_b32 v2, 1
    if readlane == Some(true) {
        branch.extend_from_slice(&[0xD760_0007, 0x0001_0101]);
    }
    branch.extend_from_slice(&ds(DS_WRITE_B32, 0, 9, 2));
    let mut rest = ds(DS_READ_B32, 3, 9, 0).to_vec();
    rest.push(0x7E0C_02FF); // v_mov_b32 v6, lit
    rest.push(2);
    // (a flag region writes only the flag's own constant, which v2 holds; else another value)
    rest.extend_from_slice(&ds(DS_WRITE_B32, 0, 9, if flag_only { 2 } else { 6 }));
    branch.extend_from_slice(&[0xBF07_8001, 0xBF85_0000 | rest.len() as u32]);
    branch.extend_from_slice(&rest);
    body.extend_from_slice(&[0x7D88_0000, 0xBE8C_246A, 0xBF88_0000 | branch.len() as u32]);
    body.extend_from_slice(&branch);
    body.push(0xBEFE_040C); // s_mov_b64 exec, s[12:13]
    body.extend_from_slice(&ds(DS_READ_B32, 5, 9, 0));
    body.extend_from_slice(&[
        0x4A0A_0A81, // v_add_nc_u32 v5, 1, v5
        0x3402_0082, // v_lshlrev_b32 v1, 2, v0
        0x38 << 26 | 0x1C << 18 | 1 << 12,
        0x80 << 24 | 2 << 16 | 5 << 8 | 1, // buffer_store_dword v5, v1, s[8:11], 0 offen
    ]);
    let mut words = vec![
        0xBE85_0380, // s_mov_b32 s5, 0
        0x3D << 26 | 0x02 << 18 | 8 << 6 | 2,
        125 << 25, // s_load_dwordx4 s[8:11], s[4:5], 0
    ];
    words.extend_from_slice(&body);
    words.push(S_ENDPGM);
    NativeProgram {
        stage: HwStage::Cs,
        wave64: true,
        vgprs: 16,
        layout: vec![
            RootParam {
                root: RootType::Constants,
                table_offset_dwords: 0,
                sgprs: 4,
                base_register: 0,
                user_data: 0,
                slot: 0,
            },
            RootParam {
                root: RootType::Table,
                table_offset_dwords: 0,
                sgprs: 1,
                base_register: 0,
                user_data: 4,
                slot: 1,
            },
        ],
        used: vec![UsedResource {
            kind: ResourceType::Uav,
            root: RootType::Table,
            table_offset_dwords: 0,
            lower_bound: 0,
            stride: 0,
            dwords: 4,
            user_data: 4,
            slot: 1,
        }],
        io: StageIo::Cs(ComputeIo { rsrc2: 5 << 1 | 1 << 15, threads: [threads, 1, 1] }),
        code: words.iter().flat_map(|w| w.to_le_bytes()).collect(),
    }
}

fn sites_of(native: &NativeProgram) -> Vec<String> {
    let p = crate::spill::build(native).expect("build");
    let st = structure::structure(&p).expect("structure");
    lower::wave64_sites(&p, &st)
}

#[test]
fn a_region_that_reads_and_writes_lds_is_named_with_its_branch_and_accesses() {
    let sites = sites_of(&flag_region_program(128, None, false));
    assert_eq!(
        sites,
        ["LDS region B1,B2 (flag region: no) around B0(s_cbranch_execz@0x20(B0)): \
          reads ds_read_b32@0x38(B2); writes ds_write_b32@0x28(B1) ds_write_b32@0x48(B2)"]
    );
}

#[test]
fn a_region_that_only_raises_a_flag_is_named_as_one() {
    let sites = sites_of(&flag_region_program(1024, None, true));
    assert_eq!(sites.len(), 1, "{sites:?}");
    assert!(sites[0].starts_with("LDS region B1,B2 (flag region: yes) around B0("), "{sites:?}");
}

#[test]
fn a_lane_crossing_instruction_is_named_with_whether_every_lane_runs_it() {
    let all = sites_of(&flag_region_program(128, Some(false), false));
    assert!(all.contains(&"v_readlane x1: 0x10(B0,all)".to_owned()), "{all:?}");
    let lane = sites_of(&flag_region_program(128, Some(true), false));
    assert!(lane.iter().any(|l| l.starts_with("v_readlane x1: 0x") && l.ends_with(",lane)")), "{lane:?}");
    // none where the program has none
    let none = sites_of(&flag_region_program(128, None, false));
    assert!(none.iter().all(|l| !l.starts_with("v_")), "{none:?}");
}

#[test]
fn the_sites_of_a_program_do_not_depend_on_its_thread_group() {
    // (the group decides whether a region is refused, not where it is)
    let a = sites_of(&flag_region_program(64, Some(false), false));
    let b = sites_of(&flag_region_program(1024, Some(false), false));
    assert_eq!(a, b);
}
