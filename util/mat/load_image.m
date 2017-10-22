function I = load_image(image_fname,color)

if(~exist('color','var'))
    color = 0;
end
I = imread(image_fname);
if(color)
    if ndims(I) == 3
        I = im2double(I);
    else
        I = im2double(repmat(I,[1 1 3]));
    end
else
    if ndims(I) == 3
        I = im2double(rgb2gray(I));
    else
        I = im2double(I);
    end
end
