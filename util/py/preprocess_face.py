#!/usr/local/bin/python
import os;
import numpy as np
import json
import glob
import sys
from StringIO import StringIO

prefix = sys.argv[1];

margin_ratio = 0.15
rectified_size = 50;
put_annotation = False

def make_square(box):
	cx = box[0] + box[2] / 2;
	cy = box[1] + box[3] / 2;
	half_side = min(box[2], box[3]) / 2;
	return [cx - half_side, cy - half_side, 2 * half_side + 1, 2 * half_side + 1]

def convert_img(filename, box, r, annotation=None):
	if annotation is not None:
		annotation_command = "-fill '#0008'"
		annotation_command += \
		    "".join([" -draw 'rectangle %d,%d,%d,%d'" % (x - 2, y - 2, x + 2, y + 2) for x, y in zip(annotation["x"], annotation["y"])])
	else:
		annotation_command = "";

	command = "convert %s.png -crop %dx%d+%d+%d -resize %dx%d %s %s%s.png" % (filename, int(box[2]), int(box[3]), int(box[0]), int(box[1]), r, r, annotation_command, prefix, filename)
	# print(command)

	if any(x < 0 for x in box) or r < 0:
		print command;
	else:
		os.system(command)

num_landmarks = 68;
# Indices start from zero.
selected_indices = [v - 1 for v in [37, 40, 43, 46, 34, 49, 55]]

annotation = {
	"num_landmarks" : num_landmarks
};

count = 0;
for filename in glob.glob("*.pts"):
	lm_data = os.popen("sed -n '4,71p' " + filename).read();
	# print(lm_data)
	landmarks = np.loadtxt(StringIO(lm_data));
	if landmarks.shape[0] != num_landmarks: continue;

	# Expand it
	imgname, ext = os.path.splitext(filename)
	w, h = os.popen('identify -format "%wx%h" ' + imgname + '.png').read().split("x")
	w, h = int(w), int(h)

	max_limits = np.amax(landmarks, axis=0);
	min_limits = np.amin(landmarks, axis=0);
	w_win, h_win = max_limits[0] - min_limits[0], max_limits[1] - min_limits[1]

	w_margin, h_margin = w_win * margin_ratio, h_win * margin_ratio

	max_limits[0] = min(max_limits[0] + w_margin, w - 1)
	max_limits[1] = min(max_limits[1] + h_margin, h - 1)
	min_limits[0] = max(min_limits[0] - w_margin, 0)
	min_limits[1] = max(min_limits[1] - h_margin, 0)

	# print(max_limits)
	# print(min_limits)
	box = [ min_limits[0], min_limits[1],
	        max_limits[0] - min_limits[0], max_limits[1] - min_limits[1]]

	# Make the box square.
	box = make_square(box)

	scale = float(rectified_size) / box[2];

	# if box[2] > box[3]:
	# 	scale = float(rectified_size) / box[3];
	# 	r = [int(box[2] * scale), rectified_size]
	# else:
	# 	scale = float(rectified_size) / box[2];
	# 	r = [rectified_size, int(box[3] * scale)]

	# Crop and resize.
	# Then open the file and only crop the image.
	anno = {
	   "x" : [int((v - box[0]) * scale + 0.5) for v in landmarks[selected_indices, 0]],
	   "y" : [int((v - box[1]) * scale + 0.5) for v in landmarks[selected_indices, 1]],
	}

	if put_annotation:
	    convert_img(imgname, box, rectified_size, annotation=anno)
	else:
            convert_img(imgname, box, rectified_size)
	annotation.update({ prefix + imgname + ".png" : anno })
	count += 1;

annotation.update({ "num_images" : count })
json.dump(annotation, open("landmarks.json", "w"), sort_keys=True, indent=4);
