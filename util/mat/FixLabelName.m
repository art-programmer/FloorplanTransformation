function label = FixLabelName(label)
%fixes the characters that are problems for file names

ndx = strfind(label,'/');
label(ndx) = '-';
ndx = strfind(label,'\');
label(ndx) = '-';
