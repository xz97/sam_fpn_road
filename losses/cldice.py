# losses/cldice.py
import torch
import torch.nn.functional as F

def _soft_erode(img):
    # img: [B,1,H,W]
    p1 = -F.max_pool2d(-img, (3, 1), stride=1, padding=(1, 0))
    p2 = -F.max_pool2d(-img, (1, 3), stride=1, padding=(0, 1))
    return torch.min(p1, p2)

def _soft_dilate(img):
    return F.max_pool2d(img, 3, stride=1, padding=1)

def _soft_open(img):
    return _soft_dilate(_soft_erode(img))

def soft_skel(img, iters=10):
    """
    Soft skeletonization. img in [0,1], shape [B,1,H,W]
    """
    skel = torch.zeros_like(img)
    opened = _soft_open(img)
    delta = F.relu(img - opened)
    skel = skel + delta

    for _ in range(iters - 1):
        img = _soft_erode(img)
        opened = _soft_open(img)
        delta = F.relu(img - opened)
        skel = skel + delta

    return skel

def cldice_loss(pred_prob, gt_mask, iters=10, smooth=1e-6):
    """
    pred_prob: [B,H,W] in [0,1]
    gt_mask  : [B,H,W] in {0,1} (float ok)
    returns  : 1 - soft_clDice
    """
    p = pred_prob.unsqueeze(1).clamp(0, 1)
    g = gt_mask.unsqueeze(1).clamp(0, 1)

    skel_p = soft_skel(p, iters=iters)
    skel_g = soft_skel(g, iters=iters)

    # Topology precision / sensitivity
    tprec = (skel_p * g).sum(dim=(1,2,3)) / (skel_p.sum(dim=(1,2,3)) + smooth)
    tsens = (skel_g * p).sum(dim=(1,2,3)) / (skel_g.sum(dim=(1,2,3)) + smooth)

    cl = (2 * tprec * tsens + smooth) / (tprec + tsens + smooth)
    loss = 1.0 - cl
    return loss.mean()
