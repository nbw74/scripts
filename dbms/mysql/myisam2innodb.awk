#!/usr/bin/awk -f
#

BEGIN {}

! /ENGINE=MyISAM/ {
    print( $0 );
}

/ENGINE=MyISAM/ {
    if( ! match(E, /FULLTEXT/) ) {
	if( ! match($0, /mysql>/)  ) {
	    sub(/ENGINE=MyISAM/, "ENGINE=InnoDB" );
	}
    }
    print( $0 );
}

{
    E = $0;
}

END {}
