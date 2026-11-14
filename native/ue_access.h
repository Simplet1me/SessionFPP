#pragma once
#pragma warning(push)
#pragma warning(disable:4251)
#include "ue4ss_abi.h"
#pragma warning(pop)
// Non-virtual declarations matched to exports in the installed UE4SS 3.0.1 DLL.
// UObject/FProperty are layout-free views of game memory; never instantiate them.
namespace RC::Unreal {
struct FUObjectItem;
class UObjectBase {
public:
    __declspec(dllimport) FUObjectItem* GetObjectItem();
};
class UObjectArray {
public:
    __declspec(dllimport) static bool IsValid(FUObjectItem*,bool);
};
class FField {
public:
    __declspec(dllimport) std::wstring GetFullName();
    __declspec(dllimport) std::wstring GetName();
    static FField* next(FField* field) {return field->GetNext();}
private:
    __declspec(dllimport) FField*& GetNext();
};
class FProperty : public FField {
public:
    __declspec(dllimport) const int& GetElementSize() const;
    __declspec(dllimport) const int& GetOffset_Internal() const;
};
class FBoolProperty : public FProperty {
public:
    __declspec(dllimport) void SetPropertyValue(void*,bool);
};
class UStruct : public UObject {
public:
    __declspec(dllimport) FField*& GetChildProperties();
};
class UFunction : public UStruct {
public:
    __declspec(dllimport) const unsigned short& GetParmsSize() const;
    __declspec(dllimport) const unsigned char& GetNumParms() const;
    __declspec(dllimport) const unsigned short& GetReturnValueOffset() const;
};
namespace Hook {
    __declspec(dllimport) void RegisterProcessEventPostCallback(std::function<void(UObject*,UFunction*,void*)>);
}
}
