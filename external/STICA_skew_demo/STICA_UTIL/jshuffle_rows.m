function b=jshuffle_rows(a);[r c]=size(a);newr=randperm(r);b=a(newr,:);