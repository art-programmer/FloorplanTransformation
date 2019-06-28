We used Torch for our experiments. Here we provide a PyTorch version which is not well-tested.

## Dependencies
```bash
pip install -r requirements.txt
```

## Training
```bash
python train.py --restore=0
```
Set *restore=1* to resume training from a checkpoint.

## Pre-trained model
We provide the pretrained checkpoint [here](https://drive.google.com/open?id=1e5c7308fdoCMRv0w-XduWqyjYPV4JWHS).

## Testing
```bash
python train.py --task=test
```
