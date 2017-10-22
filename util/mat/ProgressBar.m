function fig = ProgressBar(fig,n,N,tStr)

if nargin > 1
    if(n==0)
        tic;
    end
    clf(fig)
    ha = subplot(1,1,1, 'parent', fig); cla(ha)
    p = patch([0 1 1 0],[0 0 1 1],'w','EraseMode','none', 'parent', ha);
    p = patch([0 1 1 0]*n/N,[0 0 1 1],'g','EdgeColor','k','EraseMode','none', 'parent', ha);
    axis(ha,'off')
    if(~exist('tStr','var'))
        tStr = '';
    end
    title(sprintf('%d/%d (%.1f/%.1f mins) %s',n,N,toc/60,(N/n)*(toc/60),tStr), 'parent', ha)
    drawnow
else
    % Create counter figure
    screenSize = get(0,'ScreenSize');
    pointsPerPixel = 72/get(0,'ScreenPixelsPerInch');
    width = 360 * pointsPerPixel;
    height = 75 * pointsPerPixel;
    pos = [screenSize(3)/2-width/2 screenSize(4)/2-height/2 width height];
    titleStr = '';
    if(exist('fig','var'))
        titleStr = fig;
    end
    fig = figure('Units', 'points', ...
        'NumberTitle','off', ...
        'Name',titleStr, ...
        'IntegerHandle','off', ...
        'MenuBar', 'none', ...
        'Visible','on',...
        'position', pos,...
        'BackingStore','off',...
        'DoubleBuffer','on');
    tic;
end