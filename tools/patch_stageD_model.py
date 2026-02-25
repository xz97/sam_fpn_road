from pathlib import Path

SRC = Path("model.py")
DST = Path("model_stageD.py")
text = SRC.read_text()

def must_find(s: str):
    if s not in text:
        raise RuntimeError(f"Anchor not found: {s!r}")

# ----------------------------
# A) Patch __init__ TOPONet/FPN/CNNStem block
# Replace between:
#   "# ---- Stage C: FPN ..."  and "#### LORA"
# ----------------------------
start_anchor = '        # ---- Stage C: FPN (Phase-1 uses only P4 for map_decoder) ----\n'
end_anchor = '        #### LORA\n'
must_find(start_anchor)
must_find(end_anchor)

start = text.index(start_anchor)
end = text.index(end_anchor)

new_block = """        # ---- Stage C/D: FPN + Stage D CNN stem (Phase-1 uses only P4 for map_decoder) ----
        self.use_fpn = getattr(config, "USE_FPN", False)

        # Stage D switches (new config keys,兼容旧字段)
        self.use_cnn_stem = bool(getattr(config, "USE_CNN_STEM", getattr(config, "use_cnn_stem", False)))
        self.stageD_use_p4_only = bool(getattr(config, "STAGE_D_PHASE1_USE_P4_ONLY", True))

        # FPN output dim (兼容 FPN_OUT_DIM / FPN_OUT_CHANNELS)
        self.fpn_out_dim = int(getattr(config, "FPN_OUT_CHANNELS", getattr(config, "FPN_OUT_DIM", 256)))

        # CNN stem dims (兼容旧字段 STEM_C3_DIM/STEM_C4_DIM)
        self.stem_c3_dim = int(getattr(config, "CNN_STEM_OUT_C3", getattr(config, "STEM_C3_DIM", 256)))
        self.stem_c4_dim = int(getattr(config, "CNN_STEM_OUT_C4", getattr(config, "STEM_C4_DIM", 256)))

        # Fusion settings (兼容旧字段 FUSE_METHOD)
        self.fuse_type = str(getattr(config, "FUSE_TYPE", getattr(config, "FUSE_METHOD", "concat_1x1")))
        self.fuse_out_dim = int(getattr(config, "FUSE_OUT_CHANNELS", self.fpn_out_dim))

        # Build modules
        # Stage D: requires FPN on
        if self.use_cnn_stem:
            self.use_fpn = True

        if self.use_fpn:
            if self.use_cnn_stem:
                # FPN in: {C3(real 1/8), C4_fused(1/16), C5(1/32)}
                self.fpn = SimpleFPN(
                    in_channels_list=[self.stem_c3_dim, self.fuse_out_dim, self.fuse_out_dim],
                    out_channels=self.fpn_out_dim
                )
            else:
                # Stage C: pseudo C3 from S4
                self.fpn = SimpleFPN(
                    in_channels_list=[encoder_output_dim, encoder_output_dim, encoder_output_dim],
                    out_channels=self.fpn_out_dim
                )

        if self.use_cnn_stem:
            # 你文件里已经有 CNNStem 类：CNNStem(in_ch=3, c3_dim=..., c4_dim=...)
            self.cnn_stem = CNNStem(in_ch=3, c3_dim=self.stem_c3_dim, c4_dim=self.stem_c4_dim)

            if self.fuse_type != "concat_1x1":
                raise ValueError(f"Unsupported FUSE_TYPE/FUSE_METHOD={self.fuse_type}. Use 'concat_1x1' for Stage D Phase-1.")

            # fuse: concat(C4_cnn, S4) -> 1x1 conv -> C4_fused
            # 注意：S4 channel = encoder_output_dim (SAM out_chans=256)
            self.fuse_conv = nn.Conv2d(self.stem_c4_dim + encoder_output_dim, self.fuse_out_dim, kernel_size=1)
            self.c5_down = nn.MaxPool2d(kernel_size=2, stride=2)

"""

text = text[:start] + new_block + text[end:]

# ----------------------------
# B) Patch forward() and infer_masks_and_img_features()
# Replace the Stage C "if self.use_fpn: c4=image_embeddings ..." block with Stage D branch.
# We do exact match based on your previous Stage C code.
# ----------------------------
stageC_mask_block = """            if self.use_fpn:
                c4 = image_embeddings                                  # 1/16
                c5 = F.max_pool2d(c4, kernel_size=2, stride=2)         # 1/32
                c3 = F.interpolate(c4, scale_factor=2, mode="nearest") # 1/8 (pseudo)
                p3, p4, p5 = self.fpn(c3, c4, c5)

                mask_logits = self.map_decoder(p4)  # Phase-1: only use P4
            else:
                mask_logits = self.map_decoder(image_embeddings)

            mask_scores = torch.sigmoid(mask_logits)
"""
must_find(stageC_mask_block)

stageD_mask_block = """            if self.use_cnn_stem:
                # ===== Stage D =====
                # CNN stem provides real C3(1/8) and C4_cnn(1/16)
                c3, c4_cnn = self.cnn_stem(x)

                # SAM provides S4=image_embeddings (1/16)
                s4 = image_embeddings

                # fuse at 1/16: concat + 1x1
                c4 = self.fuse_conv(torch.cat([c4_cnn, s4], dim=1))  # C4_fused

                # C5 from downsample
                c5 = self.c5_down(c4)

                # FPN
                if self.use_fpn:
                    p3, p4, p5 = self.fpn(c3, c4, c5)
                    mask_logits = self.map_decoder(p4)  # Phase-1: only P4
                else:
                    # fallback (should not happen for Stage D)
                    mask_logits = self.map_decoder(c4)

            else:
                # ===== Stage C / baseline =====
                if self.use_fpn:
                    c4 = image_embeddings                                  # 1/16
                    c5 = F.max_pool2d(c4, kernel_size=2, stride=2)         # 1/32
                    c3 = F.interpolate(c4, scale_factor=2, mode="nearest") # 1/8 (pseudo)
                    p3, p4, p5 = self.fpn(c3, c4, c5)
                    mask_logits = self.map_decoder(p4)  # Phase-1: only use P4
                else:
                    mask_logits = self.map_decoder(image_embeddings)

            mask_scores = torch.sigmoid(mask_logits)
"""

# forward + infer 两处替换
text = text.replace(stageC_mask_block, stageD_mask_block, 2)

# ----------------------------
# C) Freeze SAM encoder if config.FREEZE_SAM_ENCODER == True
# Inject right after load_state_dict(... strict=False)
# ----------------------------
load_anchor = "            self.load_state_dict(state_dict_to_load, strict=False)\n"
must_find(load_anchor)

freeze_insert = """            self.load_state_dict(state_dict_to_load, strict=False)

            # Stage D Phase-1: freeze SAM encoder if requested
            if bool(getattr(self.config, "FREEZE_SAM_ENCODER", False)):
                for p in self.image_encoder.parameters():
                    p.requires_grad = False
"""
text = text.replace(load_anchor, freeze_insert)

# ----------------------------
# D) configure_optimizers: respect FREEZE_SAM_ENCODER and include stem/fuse/fpn params
# ----------------------------
text = text.replace(
    "if not self.config.FREEZE_ENCODER and not self.config.ENCODER_LORA:",
    "if (not bool(getattr(self.config, 'FREEZE_SAM_ENCODER', False))) and (not self.config.FREEZE_ENCODER) and (not self.config.ENCODER_LORA):"
)

# Insert extra param groups after decoder_params is added
opt_anchor = "        param_dicts += decoder_params\n\n        topo_net_params = [{\n"
must_find(opt_anchor)

opt_extra = """        param_dicts += decoder_params

        # Stage D: train stem/fuse/fpn (SAM encoder may be frozen)
        if getattr(self, "use_cnn_stem", False):
            param_dicts += [{
                'params': [p for p in self.cnn_stem.parameters() if p.requires_grad],
                'lr': self.config.BASE_LR
            },{
                'params': [p for p in self.fuse_conv.parameters() if p.requires_grad],
                'lr': self.config.BASE_LR
            }]
        if getattr(self, "use_fpn", False):
            param_dicts += [{
                'params': [p for p in self.fpn.parameters() if p.requires_grad],
                'lr': self.config.BASE_LR
            }]

        topo_net_params = [{
"""
text = text.replace(opt_anchor, opt_extra)

DST.write_text(text)
print(f"[OK] wrote {DST} from {SRC}")
