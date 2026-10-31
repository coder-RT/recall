from recall_pipeline.adapters.sam31_meta_api import parse_boxes

# a line as SAM 3.1 returned it in the probe (docs/verification.md), mask payload shortened
LINE = "<0f>0<|box;x1=472;y1=449;x2=575;y2=970;w=576;h=1024;c=0.949|><|mask;x=0;y=0;c=0.949;data=522,104,!abc|>"


def test_boxes_and_confidence_are_read_from_the_token_line():
    (b,) = parse_boxes(LINE, "laptop")
    assert b.box == (472, 449, 575, 970) and abs(b.score - 0.949) < 1e-6 and b.label == "laptop"


def test_zero_matches_is_an_empty_list():
    assert parse_boxes("", "keys") == []
