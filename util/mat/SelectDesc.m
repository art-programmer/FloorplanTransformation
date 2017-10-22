function [ desc ] = SelectDesc( desc, ndx, dim )
%SELECTDESC Summary of this function goes here
%   Detailed explanation goes here

fields = fieldnames(desc);
for i = 1:length(fields)
    if(dim == 1)
        if(iscell(desc.(fields{i})))
            for j = 1:length(desc.(fields{i}))
                desc.(fields{i}){j} = desc.(fields{i}){j}(ndx,:);
            end
        else
            ndxn = intersect(ndx,1:size(desc.(fields{i}),1));
            desc.(fields{i}) = desc.(fields{i})(ndxn,:);
        end
    else
        if(iscell(desc.(fields{i})))
            for j = 1:length(desc.(fields{i}))
                desc.(fields{i}){j} = desc.(fields{i}){j}(:,ndx);
            end
        else
            desc.(fields{i}) = desc.(fields{i})(:,ndx);
        end
    end
end

