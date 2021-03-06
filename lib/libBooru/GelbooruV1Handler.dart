import 'package:http/http.dart' as http;
import 'package:html/parser.dart';
import 'dart:async';
import 'BooruHandler.dart';
import 'BooruItem.dart';
import 'Booru.dart';
import 'package:LoliSnatcher/Tools.dart';

/**
 * Booru Handler for the gelbooru engine
 */
class GelbooruV1Handler extends BooruHandler{
  // Dart constructors are weird so it has to call super with the args
  GelbooruV1Handler(Booru booru,int limit): super(booru,limit);
  bool tagSearchEnabled = false;
  /**
   * This function will call a http get request using the tags and pagenumber parsed to it
   * it will then create a list of booruItems
   */
  Future Search(String tags,int pageNum) async{
    isActive = true;
    if(tags == " " || tags == ""){
      tags="all";
    }
    // if(this.pageNum == pageNum){
    //   return fetched;
    // }
    this.pageNum = pageNum;
    if (prevTags != tags){
      fetched = [];
    }
    String url = makeURL(tags);
    print(url);
    try {
      int length = fetched.length;
      Uri uri = Uri.parse(url);
      final response = await http.get(uri, headers: {"Accept": "text/html,application/xml", "user-agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:83.0) Gecko/20100101 Firefox/83.0"});
      // 200 is the success http response code
      if (response.statusCode == 200) {
        var document = parse(response.body);
        var spans = document.getElementsByClassName("thumb");
          for (int i = 0; i < spans.length; i++){
            if (spans.elementAt(i).children[0].firstChild!.attributes["src"] != null){
              String id = spans.elementAt(i).children[0].attributes["id"]!.substring(1);
              String thumbURL = spans.elementAt(i).children[0].firstChild!.attributes["src"]!;
              String fileURL = thumbURL.replaceFirst("thumbs", "img").replaceFirst("thumbnails", "images").replaceFirst("thumbnail_", "");
              List<String> tags = spans.elementAt(i).children[0].firstChild!.attributes["title"]!.split(" ");
              /**
               * Add a new booruitem to the list .getAttribute will get the data assigned to a particular tag in the xml object
               */
              fetched.add(BooruItem(
                fileURL: fileURL,
                sampleURL: fileURL,
                thumbnailURL: thumbURL,
                tagsList: tags,
                postURL: makePostURL(id),
              ));
              if(dbHandler!.db != null){
                setTrackedValues(fetched.length - 1);
              }
            }
          }
        // Create a BooruItem for each post in the list
        prevTags = tags;
        if (fetched.length == length){locked = true;}
        isActive = false;
        return fetched;
      }
    } catch(e) {
      print(e);
      isActive = false;
      return fetched;
    }

    }
    // This will create a url to goto the images page in the browser
    String makePostURL(String id){
      return "${booru.baseURL}/index.php?page=post&s=view&id=$id";
    }
    // This will create a url for the http request
    String makeURL(String tags){
      return "${booru.baseURL}/index.php?page=post&s=list&tags=${tags.replaceAll(" ", "+")}&pid=${(pageNum * 20).toString()}";
    }
}