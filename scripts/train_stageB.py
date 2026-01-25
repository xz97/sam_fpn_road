import os
import json
import subprocess
import socket
import datetime
from argparse import ArgumentParser

import lightning.pytorch as pl
from lightning.pytorch.callbacks import ModelCheckpoint, LearningRateMonitor
from lightning.pytorch.loggers import CSVLogger

import torch
from torch.utils.data import DataLoader

from utils import load_config
from dataset import SatMapDataset, graph_collate_fn
from model import SAMRoad


def get_git_commit():
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    except Exception:
        return "unknown"


def _safe_dump_config(config, path_json):
    """
    Best-effort to dump effective config for reproducibility.
    Works for dict / argparse.Namespace / simple objects.
    """
    try:
        if isinstance(config, dict):
            obj = config
        else:
            # try common patterns
            obj = vars(config) if hasattr(config, "__dict__") else {k: getattr(config, k) for k in dir(config) if k.isupper()}
        with open(path_json, "w") as f:
            json.dump(obj, f, indent=2)
    except Exception as e:
        # do not fail training due to config dump
        with open(path_json, "w") as f:
            json.dump({"_dump_failed": True, "error": str(e)}, f, indent=2)


def main():
    parser = ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--run_dir", required=True)
    parser.add_argument("--resume", default=None, help="path to last.ckpt / ckpt_last.ckpt")
    parser.add_argument('--init_ckpt', default=None, type=str, help='weights-only init: load model state_dict (no optimizer/scheduler)')

    # IMPORTANT: Lightning 更推荐 16-mixed；但为兼容你旧口径，仍接受 16/32
    parser.add_argument("--precision", default=16, type=int, help="16 or 32")
    parser.add_argument("--every_n_train_steps", default=2000, type=int, help="(reserved) update interval")
    parser.add_argument("--log_every_n_steps", default=200, type=int, help="reduce console spam")
    args = parser.parse_args()

    # 0) repo root (important: dataset paths are relative like ./cityscale/...)
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    os.chdir(repo_root)

    # Speed on tensor cores (A10G)
    try:
        torch.set_float32_matmul_precision("high")
    except Exception:
        pass

    # 1) run dir structure
    run_dir = os.path.abspath(args.run_dir)
    os.makedirs(run_dir, exist_ok=True)
    ckpt_dir = os.path.join(run_dir, "checkpoints")
    os.makedirs(ckpt_dir, exist_ok=True)

    # 2) record meta (reproducibility)
    meta = {
        "time": datetime.datetime.now().isoformat(),
        "host": socket.gethostname(),
        "git_commit": get_git_commit(),
        "cmd": " ".join(os.sys.argv),
        "cwd": os.getcwd(),
        "config_path": os.path.abspath(args.config),
        "torch": torch.__version__,
        "cuda_available": torch.cuda.is_available(),
        "cuda_device": torch.cuda.get_device_name(0) if torch.cuda.is_available() else "cpu",
    }
    with open(os.path.join(run_dir, "run_meta.json"), "w") as f:
        json.dump(meta, f, indent=2)

    with open(os.path.join(run_dir, "git_commit.txt"), "w") as f:
        f.write(meta["git_commit"] + "\n")

    with open(os.path.join(run_dir, "config_path.txt"), "w") as f:
        f.write(args.config + "\n")

    # 3) load config and save effective snapshot
    config = load_config(args.config)
    _safe_dump_config(config, os.path.join(run_dir, "config_effective.json"))

    # 4) model
    net = SAMRoad(config)

    # 5) datasets / loaders
    train_ds = SatMapDataset(config, is_train=True, dev_run=False)
    val_ds   = SatMapDataset(config, is_train=False, dev_run=False)

    train_loader = DataLoader(
        train_ds,
        batch_size=config.BATCH_SIZE,
        shuffle=True,
        num_workers=config.DATA_WORKER_NUM,
        pin_memory=True,
        collate_fn=graph_collate_fn,
    )
    val_loader = DataLoader(
        val_ds,
        batch_size=config.BATCH_SIZE,
        shuffle=False,
        num_workers=config.DATA_WORKER_NUM,
        pin_memory=True,
        collate_fn=graph_collate_fn,
    )

    # 6) checkpoint policy: best + last, saved every epoch
    MONITOR = "val_loss"  # must match self.log("val_loss", ...) inside model.py
    checkpoint_callback = ModelCheckpoint(
        dirpath=ckpt_dir,
        filename="best-{epoch:02d}-{step:07d}-{" + MONITOR + ":.4f}",
        monitor=MONITOR,
        mode="min",
        save_top_k=1,              # keep only best
        save_last=True,            # keep last.ckpt
        every_n_epochs=1,          # save once per epoch
        auto_insert_metric_name=False,
    )

    lr_monitor = LearningRateMonitor(logging_interval="step")

    # 7) logger: CSV only (NO wandb)
    logger = CSVLogger(save_dir=run_dir, name="logs")

    # 8) trainer (reduce console spam)
    # - enable_progress_bar=False: stop tqdm progress bar spam
    # - log_every_n_steps: control how often metrics are printed/logged
    trainer = pl.Trainer(
        default_root_dir=run_dir,
        max_epochs=config.TRAIN_EPOCHS,
        check_val_every_n_epoch=1,
        num_sanity_val_steps=2,
        callbacks=[checkpoint_callback, lr_monitor],
        logger=logger,
        precision="16-mixed" if args.precision == 16 else 32,
        log_every_n_steps=args.log_every_n_steps,
        enable_progress_bar=False,
        enable_model_summary=False,
    )

    ckpt_path = args.resume if args.resume else None
    if ckpt_path and (not os.path.exists(ckpt_path)):
        print(f"[WARN] resume ckpt not found: {ckpt_path}. Train from scratch.")
        ckpt_path = None

    # ------------------------------
    # [INIT_CKPT] weights-only init (paper-friendly)
    # ------------------------------
    if getattr(args, 'init_ckpt', None):
        ckpt = torch.load(args.init_ckpt, map_location='cpu')
        state_dict = ckpt.get('state_dict', ckpt)
        missing, unexpected = net.load_state_dict(state_dict, strict=False)
        print(f"[INIT_CKPT] loaded: {args.init_ckpt}")
        print(f"[INIT_CKPT] missing={len(missing)} unexpected={len(unexpected)}")
        if missing:
            print('[INIT_CKPT] missing(sample):', missing[:20])
        if unexpected:
            print('[INIT_CKPT] unexpected(sample):', unexpected[:20])

    trainer.fit(net, train_dataloaders=train_loader, val_dataloaders=val_loader, ckpt_path=ckpt_path)

    print("[OK] done. run_dir =", run_dir)
    print("[OK] best_ckpt =", checkpoint_callback.best_model_path)
    print("[OK] last_ckpt =", os.path.join(ckpt_dir, "last.ckpt"))


if __name__ == "__main__":
    main()
