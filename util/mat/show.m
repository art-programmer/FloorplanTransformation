% SHOW - Displays an image with the right size and colors and with a title.
%
% Usage:   h = show(im, figNo, title)
%
% Arguments:  im    - Either a 2 or 3D array of pixel values or the name
%                     of an image file;
%             figNo - Optional figure number to display image in. If
%                     figNo is 0 the current figure or subplot is
%                     assumed.
%             title - Optional string specifying figure title
%
% Returns:    h     - Handle to the figure.  This allows you to set
%                     additional figure attributes if desired.
%
% The function displays the image, automatically setting the colour map to
% grey if it is a 2D image, or leaving it as colour otherwise, and setting
% the axes to be 'equal'.  The image is also displayed as 'TrueSize', that
% is, pixels on the screen match pixels in the image (if it is possible
% to fit it on the screen, otherwise MATLAB rescales it to fit).
%
% Unless you are doing a subplot (figNo==0) the window is sized to match
% the image, leaving no border, and hence saving desktop real estate.
%
% If figNo is omitted a new figure window is created for the image.  If
% figNo is supplied, and the figure exists, the existing window is reused to
% display the image, otherwise a new window is created. If figNo is 0 the
% current figure or subplot is assumed.

% Copyright (c) 2000-2007 Peter Kovesi
% School of Computer Science & Software Engineering
% The University of Western Australia
% http://www.csse.uwa.edu.au/
% 
% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, subject to the following conditions:
% 
% The above copyright notice and this permission notice shall be included in 
% all copies or substantial portions of the Software.
%
% The Software is provided "as is", without warranty of any kind.

% October   2000  Original version
% March     2003  Mods to alow figure name in window bar and allow for subplots.
% April     2007  Proper recording and restoring of MATLAB warning state.
% September 2008 Octave compatible

function h = show(im, figNo, usecbar, Title)

    Octave = exist('OCTAVE_VERSION') ~= 0;  % Are we running under Octave?    
    
    s = warning('query','all'); % Record existing warning state.
    warning('off');             % Turn off warnings that might arise if image
                                % has to be rescaled to fit on screen
    
    if(~exist('usecbar','var'))
        usecbar = 1;
    end
                                
    if nargin <= 3			   
	if ~isnumeric(im) & ~islogical(im) % Guess that an image name has
                                           % been supplied 
	    Title = im;
	    im = imread(im);
	else
	    Title = inputname(1);  % Get variable name of image data
	end
    end
    
    newWindow = 1;
    if nargin >= 2
	if figNo               % We have a valid figure number
	    figure(figNo);     % Reuse or create a figure window with
                               % this number
            if ~Octave			       
		subplot('position',[0 0 1 1]); % Use the whole window
	    end
	else                   
	    newWindow=0;       % figNo == 0
	end
    else
	figNo = figure;        % Create new figure window
	if ~Octave
	    subplot('position',[0 0 1 1]); % Use the whole window
	end	    
    end

    if ndims(im) == 2          % Display as greyscale
	imagesc(im)
    if(usecbar)colorbar;end
	%colormap('gray');
    else
	imshow(im)             % Display as RGB
    end

    if newWindow            
	axis('image'), axis('off')
	set(figNo,'name', ['  ' Title])
	if ~Octave
        [rows cols ch] = size(im);
	    truesize(figNo,[rows cols]);
	end
    else                          % Assume we are trying to do a subplot 
	axis('image'), axis('off')
	title(Title) % Use a title rather than rename the figure	
    end

    if nargout == 1
       h = figNo;
    end

    warning(s);  % Restore warnings

    


