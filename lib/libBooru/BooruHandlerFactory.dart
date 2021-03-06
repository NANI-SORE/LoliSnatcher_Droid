import 'package:LoliSnatcher/libBooru/BooruHandler.dart';
import 'package:LoliSnatcher/libBooru/FavouritesHandler.dart';
import 'package:LoliSnatcher/libBooru/RainbooruHandler.dart';

import 'Booru.dart';
import 'BooruItem.dart';
import 'BooruOnRailsHandler.dart';
import 'DBHandler.dart';
import 'DanbooruHandler.dart';
import 'GelbooruHandler.dart';
import 'GelbooruV1Handler.dart';
import 'HydrusHandler.dart';
import 'MoebooruHandler.dart';
import 'PhilomenaHandler.dart';
import 'SankakuHandler.dart';
import 'ShimmieHandler.dart';
import 'SzurubooruHandler.dart';
import 'e621Handler.dart';
import 'WorldHandler.dart';
import 'R34HentaiHandler.dart';
import 'IdolSankakuHandler.dart';

class BooruHandlerFactory{
  BooruHandler? booruHandler;
  int pageNum = -1;
  List getBooruHandler(Booru booru, int limit, DBHandler? dbHandler){
    switch (booru.type) {
      case("Moebooru"):
        pageNum = 0;
        booruHandler = new MoebooruHandler(booru, limit);
        break;
      case("Gelbooru"):
        booruHandler = new GelbooruHandler(booru, limit);
        break;
      case("Danbooru"):
        pageNum = 0;
        booruHandler = new DanbooruHandler(booru, limit);
        break;
      case("e621"):
        pageNum = 0;
        booruHandler = new e621Handler(booru, limit);
        break;
      case("Shimmie"):
        pageNum = 0;
        booruHandler = new ShimmieHandler(booru, limit);
        break;
      case("Philomena"):
        pageNum = 0;
        booruHandler = new PhilomenaHandler(booru, limit);
        break;
      case("Szurubooru"):
        booruHandler = new SzurubooruHandler(booru, limit);
        break;
      case("Sankaku"):
        pageNum = 0;
        booruHandler = new SankakuHandler(booru, limit);
        break;
      case("Hydrus"):
        booruHandler = new HydrusHandler(booru, limit);
        break;
      case("GelbooruV1"):
        booruHandler = new GelbooruV1Handler(booru, limit);
        break;
      case("BooruOnRails"):
        pageNum = 0;
        booruHandler = new BooruOnRailsHandler(booru, limit);
        break;
      case("Favourites"):
        booruHandler = new FavouritesHandler(booru, limit);
        break;
      case("Rainbooru"):
        pageNum = 0;
        booruHandler = new RainbooruHandler(booru, limit);
        break;
      case("R34Hentai"):
        pageNum = 0;
        booruHandler = new R34HentaiHandler(booru, limit);
        break;
      case("World"):
        booruHandler = new WorldHandler(booru, limit);
        break;
      case("IdolSankaku"):
        pageNum = 0;
        booruHandler = new IdolSankakuHandler(booru, limit);
        break;
    }
    booruHandler!.dbHandler = dbHandler;
    return [booruHandler, pageNum];
  }
}