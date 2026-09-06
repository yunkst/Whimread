import '../../../models/prompt_tag_category.dart';

abstract class IPromptTagCategoryRepository {
  Future<List<PromptTagCategory>> getAll();
  Future<int> save(PromptTagCategory category);
  Future<void> delete(int id);
  Future<void> reorder(List<int> orderedIds);
  Future<int> count();
  Future<void> initDefaultCategories();
}
