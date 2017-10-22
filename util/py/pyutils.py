import sys
import os

def compute_line_limits(w, rect):
    '''For a line defined as ax + by + c = 0, find its two endpoints within the bounding box [x1, y1, x2, y2]'''
    # First check the sign of the four points.
    a, b, c = w
    x1, y1, x2, y2 = rect

    ax1 = a * x1
    ax2 = a * x2
    by1 = b * y1
    by2 = b * y2
    s11 = ax1 + by1 + c
    s12 = ax1 + by2 + c
    s21 = ax2 + by1 + c
    s22 = ax2 + by2 + c

    intersect = []
    if s11 * s21 < 0: intersect.append( (-(c+by1) / float(a), y1) )
    if s21 * s22 < 0: intersect.append( (x2, -(c+ax2) / float(b)) )
    if s12 * s22 < 0: intersect.append( (-(c+by2) / float(a), y2) )
    if s11 * s12 < 0: intersect.append( (x1, -(c+ax1) / float(b)) )

    if len(intersect) < 2:
        if s11 == 0: intersect.append((x1, y1))
        if s12 == 0: intersect.append((x1, y2))
        if s21 == 0: intersect.append((x2, y1))
        if s22 == 0: intersect.append((x2, y2))

    return intersect
