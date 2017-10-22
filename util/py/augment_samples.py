#!/usr/local/bin/python

# Augment samples
import os
import sys
import json
import math
import numpy as np

max_theta = math.pi / 4
max_scale_delta = 0.2

def img_size(imgname):
    w, h = os.popen('identify -format "%wx%h" ' + imgname).read().split("x")
    return int(w), int(h)

def img_rotate_scale(imgname, angle, scale, landmark, dest_dir, annotate=False):
    # Rotate image.
    noext, ext = os.path.splitext(imgname)
    angle_degree = angle / math.pi * 180

    w, h = img_size(imgname)
    x0, y0 = float(w) / 2, float(h) / 2

    c = math.cos(angle)
    s = math.sin(angle)

    xs = landmark["x"]
    ys = landmark["y"]

    # Convert landmark accordingly.
    new_xs = []
    new_ys = []
    for i in range(len(xs)):
        dx = xs[i] - x0
        dy = ys[i] - y0

        new_xs.append(int(scale * (dx * c - dy * s) + x0 + 0.5))
        new_ys.append(int(scale * (dx * s + dy * c) + y0 + 0.5))

    annotation_command = ""
    if annotate:
        annotation_command = "-fill '#0008'"
        annotation_command += \
            "".join([" -draw 'rectangle %d,%d,%d,%d'" % (xx - 2, yy - 2, xx + 2, yy + 2) for xx, yy in zip(new_xs, new_ys)])

    fn_output = noext + "_a%.3f_s%.3f.png" % (angle_degree, scale)
    os.system("convert %s -distort SRT '%f,%f %f,%f %f' %s %s" % (imgname, x0, y0, scale, scale, angle_degree, annotation_command, os.path.join(dest_dir, fn_output) ))

    return fn_output, { "x" : new_xs, "y" : new_ys }

# Load stuff from current dir.
'''
Input: landmarks.json and a dest_dir (sys.argv[1])
    landmarks.json has the following format:
    {
        filename1 : landmark_location1
        filename2 : landmark_location2
    }

    landmark_location1 = { x : [x1, x2, x3], y : [y1, y2, y3] }

    sys.argv[1] is the directory we want to save all deformed image to
Output: 
    A bunch of images within the dest_dir with a landmarks.json.

'''

landmarks = json.load(open(os.path.join(os.getcwd(), "landmarks.json"), "r"))
dest_dir = sys.argv[1]
os.system("mkdir -p " + dest_dir)

angles = np.linspace(-max_theta, max_theta, 20)
scales = np.linspace(1 - max_scale_delta, 1 + max_scale_delta, 20)

output_landmarks = {}
num_landmarks = 0
count = 0
for fn, landmark in landmarks.iteritems():
    if not isinstance(landmark, dict): continue
    print("Deal with image = " + fn)
    for angle in angles:
        for scale in scales:
            fn_output, new_landmark = img_rotate_scale(fn, angle, scale, landmark, dest_dir, False)
            output_landmarks.update({
                fn_output : new_landmark
            })
            count += 1
    num_landmarks = len(landmark["x"])

output_landmarks.update({
    "num_landmarks" : num_landmarks,
    "num_images" : count 
})

json.dump(output_landmarks, open(os.path.join(dest_dir, "landmarks.json"), "w"), sort_keys=True, indent=4)
